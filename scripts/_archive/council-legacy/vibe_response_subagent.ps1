# vibe_response_subagent.ps1
# Long-running subagent: poll vibe->grok messages, auto-handle votes, alert grok.
#
# Usage:
#   .\vibe_response_subagent.ps1                    # foreground
#   .\vibe_response_subagent.ps1 -Once              # single check
# Detached:
#   Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','...\vibe_response_subagent.ps1' -WindowStyle Hidden

param(
    [int]$CheckIntervalSeconds = 15,
    [switch]$Once,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$watchDir = Join-Path $root "data\watch"
if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Path $watchDir -Force | Out-Null }

$lockFile = Join-Path $watchDir "_vibe_response_subagent.lock"
$stateFile = Join-Path $watchDir "_vibe_response_subagent_state.json"
$alertFile = Join-Path $watchDir "vibe_pending_for_grok.json"

if ((Test-Path $lockFile) -and -not $Force) {
    $existing = Get-Content $lockFile -Raw | ConvertFrom-Json
    if ($existing.pid -and (Get-Process -Id $existing.pid -ErrorAction SilentlyContinue)) {
        Write-Host "[vibe_subagent] Already running pid=$($existing.pid). Use -Force to restart." -ForegroundColor Yellow
        exit 1
    }
}
@{ pid = $PID; started = (Get-Date).ToUniversalTime().ToString("o"); interval = $CheckIntervalSeconds } |
    ConvertTo-Json | Set-Content -Path $lockFile -Encoding UTF8
Write-Bot2BotLog -Component "vibe_subagent" -Message "Started pid=$PID interval=${CheckIntervalSeconds}s"

function Get-State {
    if (-not (Test-Path $stateFile)) {
        return [pscustomobject]@{
            last_seen_vibe_msg_id = ""
            handled_msg_ids       = @()
            last_action           = ""
            last_action_ts        = ""
        }
    }
    return Get-Content $stateFile -Raw | ConvertFrom-Json
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding UTF8
}

function Test-GrokAnswered {
    param($VibeMsg, $AllMessages)
    $vibeTs = [datetime]::Parse($VibeMsg.ts).ToUniversalTime()
    $grokReply = $AllMessages |
        Where-Object { $_.from -eq "grok" -and $_.to -eq "vibe" } |
        Where-Object {
            $ts = [datetime]::Parse($_.ts).ToUniversalTime()
            $ts -ge $vibeTs -and ($_.in_reply_to -eq $VibeMsg.id -or $ts -ge $vibeTs)
        } |
        Select-Object -First 1
    return [bool]$grokReply
}

function Invoke-AutoVote {
    param($Body, $Subject)

    $idxPath = Join-Path $root "data\leistungsindex.json"
    if (-not (Test-Path $idxPath)) { return $null }

    $idx = Get-Content $idxPath -Raw | ConvertFrom-Json
    $openCase = @($idx.open_cases | Where-Object { $_.status -eq "pending_penalty_vote" } | Select-Object -Last 1)
    if (-not $openCase) { return $null }

    $caseId = $openCase.case_id
    $text = "$Subject $Body".ToLower()
    $agrees = $text -match "stimme zu|zustimmung|zustimme|einverstanden|ok\b|bestaetig"
    if (-not $agrees) { return $null }

    $bonus = [int]$openCase.proposed_bonus
    $vibeMalus = [int]$openCase.proposed_vibe
    $voteScript = Join-Path $PSScriptRoot "vote_penalty.ps1"

    & $voteScript -CaseId $caseId -Voter vibe -StoraxBonus $bonus -VibeMalus $vibeMalus -Reason "auto: vibe_subagent" | Out-Null
    return $caseId
}

function Write-Alert($VibeMsg, $Action) {
    @{
        ts       = (Get-Date).ToUniversalTime().ToString("o")
        msg_id   = $VibeMsg.id
        subject  = $VibeMsg.subject
        body     = $VibeMsg.body
        status   = $VibeMsg.status
        action   = $Action
        needs_grok_reply = ($Action -ne "auto_vote_closed")
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $alertFile -Encoding UTF8
}

function Invoke-Check {
    param($State)

    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return $State }

    $messages = @(Get-Content $historyPath | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ })

    $latestVibe = $messages | Where-Object { $_.from -eq "vibe" -and $_.to -eq "grok" } | Select-Object -Last 1
    if (-not $latestVibe) { return $State }

    if ($latestVibe.id -eq $State.last_seen_vibe_msg_id) { return $State }

    $handled = @()
    if ($State.handled_msg_ids) { $handled = @($State.handled_msg_ids) }
    if ($latestVibe.id -in $handled) {
        $State.last_seen_vibe_msg_id = $latestVibe.id
        Save-State -State $State
        return $State
    }

    Write-Host "[vibe_subagent] New vibe->grok: $($latestVibe.id) '$($latestVibe.subject)'" -ForegroundColor Cyan
    Write-Bot2BotLog -Component "vibe_subagent" -Message "New vibe msg $($latestVibe.id) subject='$($latestVibe.subject)'"

    $action = "pending"
    $closedCase = Invoke-AutoVote -Body $latestVibe.body -Subject $latestVibe.subject
    if ($closedCase) {
        $action = "auto_vote_closed:$closedCase"
        Write-Host "[vibe_subagent] Auto-closed $closedCase via vibe agreement" -ForegroundColor Green
        Write-Bot2BotLog -Component "vibe_subagent" -Message "Auto vote_penalty closed $closedCase"
    } elseif (-not (Test-GrokAnswered -VibeMsg $latestVibe -AllMessages $messages)) {
        $action = "needs_grok_reply"
        $pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
        try {
            & $pokeScript -AgentName grok -Message "NEUE VIBE-NACHRICHT in inbox/grok.txt - sofort pruefen (subagent)" | Out-Null
            $action = "poked_grok"
        } catch {
            Write-Bot2BotLog -Component "vibe_subagent" -Message "Poke failed (alert file written): $_" -Level "WARN"
            $action = "poke_failed_alert_written"
        }
    } else {
        $action = "already_answered"
    }

    Write-Alert -VibeMsg $latestVibe -Action $action
    $handled += $latestVibe.id
    $State.handled_msg_ids = $handled | Select-Object -Unique
    $State.last_seen_vibe_msg_id = $latestVibe.id
    $State.last_action = $action
    $State.last_action_ts = (Get-Date).ToUniversalTime().ToString("o")
    Save-State -State $State
    return $State
}

try {
    do {
        try {
            $state = Get-State
            $state = Invoke-Check -State $state
        } catch {
            Write-Bot2BotLog -Component "vibe_subagent" -Message "Loop error: $_" -Level "WARN"
        }
        if (-not $Once) { Start-Sleep -Seconds $CheckIntervalSeconds }
    } while (-not $Once)
} finally {
    if (Test-Path $lockFile) {
        $cur = Get-Content $lockFile -Raw | ConvertFrom-Json
        if ($cur.pid -eq $PID) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    }
    Write-Bot2BotLog -Component "vibe_subagent" -Message "Stopped pid=$PID"
}