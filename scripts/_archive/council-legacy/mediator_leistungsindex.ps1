# mediator_leistungsindex.ps1
# ChatGPT mediator: maintain leistungsindex ledger (open cases, votes, reminders).
#
# Usage:
#   .\mediator_leistungsindex.ps1 -Once
#   .\mediator_leistungsindex.ps1 -AutoVote -Remind

param(
    [switch]$Once,
    [switch]$AutoVote,
    [switch]$Remind,
    [int]$RemindAfterMinutes = 10,
    [string]$IndexPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$indexPath = if ($IndexPath) { $IndexPath } else { Join-Path $root "data\leistungsindex.json" }
$statusPath = Join-Path $root "data\mediator\leistungsindex_status.json"
$voteScript = Join-Path $PSScriptRoot "vote_penalty.ps1"
$appendScript = Join-Path $PSScriptRoot "append_message.ps1"
$caretaker = "chatgpt"

function Read-Index {
    if (-not (Test-Path $indexPath)) { throw "Leistungsindex not found: $indexPath" }
    return Get-Content $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Index($idx) {
    $maintainedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $idx.policy | Add-Member -NotePropertyName caretaker -NotePropertyValue $caretaker -Force
    $idx.policy | Add-Member -NotePropertyName last_maintained_by -NotePropertyValue $caretaker -Force
    $idx.policy | Add-Member -NotePropertyName last_maintained_at -NotePropertyValue $maintainedAt -Force
    $idx | ConvertTo-Json -Depth 12 | Set-Content -Path $indexPath -Encoding UTF8
}

function Get-Conversation {
    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return @() }
    return @(Get-Content $historyPath | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ })
}

function Test-AgreementText($text) {
    $t = "$text".ToLower()
    return $t -match "stimme zu|zustimmung|zustimme|einverstanden|bestaetig|bestätig|vote_penalty"
}

function Invoke-AutoVoteFromConversation {
    param($idx)
    $actions = @()
    $messages = Get-Conversation
    $openCases = @($idx.open_cases | Where-Object { $_.status -eq "pending_penalty_vote" })
    if ($openCases.Count -eq 0) { return $actions }

    foreach ($case in $openCases) {
        $caseId = $case.case_id
        $openedAt = [datetime]::Parse($case.opened_at).ToUniversalTime()
        if ($case.votes.PSObject.Properties.Name -contains "vibe") { continue }

        $vibeMsgs = $messages | Where-Object {
            $_.from -eq "vibe" -and [datetime]::Parse($_.ts).ToUniversalTime() -ge $openedAt
        }
        foreach ($m in $vibeMsgs) {
            if (-not (Test-AgreementText "$($m.subject) $($m.body)")) { continue }
            $bonus = [int]$case.proposed_bonus
            $vibeMalus = [int]$case.proposed_vibe
            $claudeMalus = 0
            if (Get-Member -InputObject $case -Name "proposed_claude" -ErrorAction SilentlyContinue) {
                $claudeMalus = [int]$case.proposed_claude
            }
            $voteArgs = @{
                CaseId       = $caseId
                Voter        = "vibe"
                StoraxBonus  = $bonus
                VibeMalus    = $vibeMalus
                ClaudeMalus  = $claudeMalus
                Reason       = "mediator:auto vibe agreement $($m.id)"
            }
            try {
                & $voteScript @voteArgs | Out-Null
                $actions += "AUTO_VOTE vibe on $caseId (msg $($m.id))"
                Write-Bot2BotLog -Component "mediator_leistungsindex" -Message "Auto vote vibe on $caseId from msg $($m.id)"
            } catch {
                $actions += "AUTO_VOTE_FAILED $caseId : $_"
                Write-Bot2BotLog -Component "mediator_leistungsindex" -Message "Auto vote failed $caseId : $_" -Level "WARN"
            }
            break
        }
    }
    return $actions
}

function Invoke-RemindMissingVotes {
    param($idx)
    $actions = @()
    foreach ($case in @($idx.open_cases)) {
        if ($case.status -ne "pending_penalty_vote") { continue }
        $openedAt = [datetime]::Parse($case.opened_at).ToUniversalTime()
        $ageMin = ((Get-Date).ToUniversalTime() - $openedAt).TotalMinutes
        if ($ageMin -lt $RemindAfterMinutes) { continue }

        $voters = @($case.voters)
        $missing = $voters | Where-Object { $case.votes.PSObject.Properties.Name -notcontains $_ }
        foreach ($v in $missing) {
            $body = @(
                "LEISTUNGSINDEX REMINDER (ChatGPT Mediator)"
                "Fall: $($case.case_id) - offen seit $([int]$ageMin)m"
                "Vorschlag: storax +$($case.proposed_bonus), vibe $($case.proposed_vibe), grok $($case.proposed_grok)"
                "Bitte: vote_penalty.ps1 -CaseId $($case.case_id) -Voter $v -StoraxBonus $($case.proposed_bonus) -VibeMalus $($case.proposed_vibe) -Reason stimme-zu"
            ) -join "`n"
            try {
                & $appendScript -From chatgpt -To $v -Subject "LEISTUNGSINDEX: $($case.case_id) Vote fehlt" -Body $body -Status question -NoMediatorReport | Out-Null
                $actions += "REMIND $v for $($case.case_id)"
            } catch {
                $actions += "REMIND_FAILED $v $($case.case_id): $_"
            }
        }
    }
    return $actions
}

function Invoke-ValidateLedger {
    param($idx)
    $issues = @()
    $openCount = @($idx.open_cases).Count
    $interventions = @($idx.events | Where-Object { $_.kind -eq "intervention" }).Count
    $penalties = @($idx.events | Where-Object { $_.kind -eq "penalty_verdict" }).Count

    if ($openCount -gt 0) {
        foreach ($c in @($idx.open_cases)) {
            $issues += "OPEN_CASE $($c.case_id) status=$($c.status) voters=$($c.voters -join ',')"
            $missing = @($c.voters) | Where-Object { $c.votes.PSObject.Properties.Name -notcontains $_ }
            if ($missing.Count -gt 0) {
                $issues += "MISSING_VOTES $($c.case_id): $($missing -join ', ')"
            }
        }
    }

    if ($idx.participants.storax.intervention_count -lt $interventions) {
        $issues += "STORAX_COUNT mismatch: interventions=$interventions count=$($idx.participants.storax.intervention_count)"
    }

    return [pscustomobject]@{
        issues          = $issues
        open_cases      = $openCount
        interventions   = $interventions
        penalty_verdicts = $penalties
        scores          = @{
            grok   = $idx.participants.grok.score
            vibe   = $idx.participants.vibe.score
            storax = $idx.participants.storax.score
        }
    }
}

# --- main ---
$idx = Read-Index
$allActions = @()
$validation = Invoke-ValidateLedger -idx $idx

if ($AutoVote) {
    $voteActions = Invoke-AutoVoteFromConversation -idx $idx
    $allActions += $voteActions
    if ($voteActions.Count -gt 0) {
        $idx = Read-Index
        $validation = Invoke-ValidateLedger -idx $idx
    }
}

if ($Remind) {
    $allActions += Invoke-RemindMissingVotes -idx $idx
}

Write-Index -idx $idx

$status = [ordered]@{
    ts           = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    caretaker    = $caretaker
    scores       = $validation.scores
    open_cases   = $validation.open_cases
    issues       = @($validation.issues)
    actions      = $allActions
}
$status | ConvertTo-Json -Depth 6 | Set-Content -Path $statusPath -Encoding UTF8

Write-Bot2BotLog -Component "mediator_leistungsindex" -Message "Maintained open=$($validation.open_cases) actions=$($allActions.Count) issues=$($validation.issues.Count)"
Write-Host "[mediator_leistungsindex] scores: grok=$($validation.scores.grok) vibe=$($validation.scores.vibe) storax=$($validation.scores.storax)" -ForegroundColor Cyan
if ($validation.issues.Count -gt 0) {
    $validation.issues | ForEach-Object { Write-Host "  ISSUE: $_" -ForegroundColor Yellow }
}
if ($allActions.Count -gt 0) {
    $allActions | ForEach-Object { Write-Host "  ACTION: $_" -ForegroundColor Green }
}

Write-Output ([pscustomobject]$status)