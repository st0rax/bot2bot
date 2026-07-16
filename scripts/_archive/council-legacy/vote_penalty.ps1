# vote_penalty.ps1
# Unanimous penalty-amount vote for an open intervention case (grok + vibe only).
#
# Usage:
#   .\vote_penalty.ps1 -CaseId INT-001 -Voter grok -StoraxBonus 5 -VibeMalus -4 -Reason "Deadlock, Grok E nicht geprueft"
#   .\vote_penalty.ps1 -CaseId INT-001 -Voter vibe -StoraxBonus 5 -VibeMalus -4 -Reason "stimme zu"
#   .\vote_penalty.ps1 -CaseId INT-003 -Voter grok -StoraxBonus 5 -VibeMalus 0 -ClaudeMalus -10 -Reason "Claude ignorierte Grok-Arbeit"

param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [ValidateSet("grok", "vibe")]
    [string]$Voter,

    [Parameter(Mandatory)]
    [int]$StoraxBonus,

    [Parameter(Mandatory)]
    [int]$VibeMalus,

    [string]$Reason = "",
    [int]$ClaudeMalus = 0,
    [int]$GrokMultiplier = 2,
    [string]$IndexPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

if ($StoraxBonus -lt 0) { throw "StoraxBonus must be >= 0 (bonus, not malus)" }
if ($VibeMalus -gt 0) { throw "VibeMalus must be <= 0 (negative = malus)" }
if ($ClaudeMalus -gt 0) { throw "ClaudeMalus must be <= 0 (negative = malus)" }
if ($GrokMultiplier -lt 1) { throw "GrokMultiplier must be >= 1" }

$root = Get-Bot2BotRoot
$indexPath = if ($IndexPath) { $IndexPath } else { Join-Path $root "data\leistungsindex.json" }
$idx = Get-Content $indexPath -Raw | ConvertFrom-Json

$case = $idx.open_cases | Where-Object { $_.case_id -eq $CaseId } | Select-Object -First 1
if (-not $case) { throw "Open case not found: $CaseId" }
if ($case.status -notin @("pending_penalty_vote", "pending_unanimous")) {
    throw "Case $CaseId status=$($case.status), not open for penalty votes"
}

if ($Voter -notin @($case.voters)) { throw "Voter $Voter not in voters list" }

function Get-VoteFieldInt {
    param($Vote, [string]$Name, [int]$Default = 0)
    if ($null -eq $Vote) { return $Default }
    if ($Vote -is [System.Collections.IDictionary]) {
        if (-not $Vote.Contains($Name)) { return $Default }
        return [int]$Vote[$Name]
    }
    if (-not (Get-Member -InputObject $Vote -Name $Name -MemberType NoteProperty, Property -ErrorAction SilentlyContinue)) {
        return $Default
    }
    return [int]$Vote.$Name
}

$grokMalus = $VibeMalus * $GrokMultiplier

$voteData = [ordered]@{
    storax_bonus     = $StoraxBonus
    vibe_malus       = $VibeMalus
    grok_malus       = $grokMalus
    claude_malus     = $ClaudeMalus
    grok_multiplier  = $GrokMultiplier
    reason           = $Reason
    ts               = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$case.votes | Add-Member -NotePropertyName $Voter -NotePropertyValue ([pscustomobject]$voteData) -Force

$voterList = @($case.voters)
$allVoted = ($voterList | ForEach-Object { $case.votes.PSObject.Properties.Name -contains $_ }) -notcontains $false

if ($allVoted) {
    $bonuses = $voterList | ForEach-Object { Get-VoteFieldInt -Vote $case.votes.$_ -Name storax_bonus }
    $vibeMaluses = $voterList | ForEach-Object { Get-VoteFieldInt -Vote $case.votes.$_ -Name vibe_malus }
    $grokMaluses = $voterList | ForEach-Object { Get-VoteFieldInt -Vote $case.votes.$_ -Name grok_malus }
    $claudeMaluses = $voterList | ForEach-Object { Get-VoteFieldInt -Vote $case.votes.$_ -Name claude_malus }

    $unanimous = (
        ($bonuses | Select-Object -Unique).Count -eq 1 -and
        ($vibeMaluses | Select-Object -Unique).Count -eq 1 -and
        ($grokMaluses | Select-Object -Unique).Count -eq 1 -and
        ($claudeMaluses | Select-Object -Unique).Count -eq 1
    )

    if ($unanimous) {
        $finalBonus = $bonuses[0]
        $finalVibeMalus = $vibeMaluses[0]
        $finalGrokMalus = $grokMaluses[0]
        $finalClaudeMalus = $claudeMaluses[0]
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        $case | Add-Member -NotePropertyName verdict -NotePropertyValue "unanimous" -Force
        $case | Add-Member -NotePropertyName status -NotePropertyValue "closed" -Force
        $case | Add-Member -NotePropertyName storax_bonus -NotePropertyValue $finalBonus -Force
        $case | Add-Member -NotePropertyName vibe_malus -NotePropertyValue $finalVibeMalus -Force
        $case | Add-Member -NotePropertyName grok_malus -NotePropertyValue $finalGrokMalus -Force
        $case | Add-Member -NotePropertyName claude_malus -NotePropertyValue $finalClaudeMalus -Force
        $case | Add-Member -NotePropertyName grok_multiplier -NotePropertyValue $GrokMultiplier -Force

        $idx.participants.storax.score += $finalBonus
        if ($finalVibeMalus -ne 0) {
            $idx.participants.vibe.score += $finalVibeMalus
            $idx.participants.vibe.fault_count += 1
        }
        if ($finalGrokMalus -ne 0) {
            $idx.participants.grok.score += $finalGrokMalus
            $idx.participants.grok.fault_count += 1
        }
        if ($finalClaudeMalus -ne 0) {
            if (-not $idx.participants.claude) {
                $idx.participants | Add-Member -NotePropertyName claude -NotePropertyValue ([pscustomobject]@{ score = 0; fault_count = 0 }) -Force
            }
            $idx.participants.claude.score += $finalClaudeMalus
            $idx.participants.claude.fault_count += 1
        }

        $delta = [ordered]@{
            storax = $finalBonus
            vibe   = $finalVibeMalus
            grok   = $finalGrokMalus
        }
        if ($finalClaudeMalus -ne 0) { $delta.claude = $finalClaudeMalus }

        $idx.events += [pscustomobject][ordered]@{
            id      = "$CaseId-penalty"
            ts      = $ts
            kind    = "penalty_verdict"
            agent   = "grok,vibe"
            delta   = $delta
            reason  = "Einstimmig: storax +$finalBonus, vibe $finalVibeMalus, grok $finalGrokMalus, claude $finalClaudeMalus. $Reason"
            context = $CaseId
        }

        $idx.open_cases = @($idx.open_cases | Where-Object { $_.case_id -ne $CaseId })
        Write-Host "[leistungsindex] $CaseId CLOSED  storax +$finalBonus  vibe $finalVibeMalus  grok $finalGrokMalus  claude $finalClaudeMalus" -ForegroundColor Green
    } else {
        $case.status = "disputed"
        Write-Host "[leistungsindex] $CaseId DISPUTED  bonus=$($bonuses -join '/') vibe=$($vibeMaluses -join '/') grok=$($grokMaluses -join '/'). Kein Malus bis Einstimmigkeit." -ForegroundColor Red
    }
} else {
    $missing = $voterList | Where-Object { $case.votes.PSObject.Properties.Name -notcontains $_ }
    Write-Host "[leistungsindex] Vote recorded ($Voter). Warte auf: $($missing -join ', ')" -ForegroundColor Cyan
}

$idx | ConvertTo-Json -Depth 12 | Set-Content -Path $indexPath -Encoding UTF8
Write-Bot2BotLog -Component "leistungsindex" -Message "Penalty vote $Voter on $CaseId bonus=$StoraxBonus vibe=$VibeMalus grok=$grokMalus status=$($case.status)"
