# watch_vibe_for_grok.ps1
# Background loop: detect new vibe -> grok messages and poke grok immediately.
#
# Usage:
#   .\watch_vibe_for_grok.ps1              # foreground
#   .\watch_vibe_for_grok.ps1 -Once        # single pass (test)
# Start detached:
#   Start-Process pwsh -ArgumentList '-NoProfile','-File','watch_vibe_for_grok.ps1' -WindowStyle Hidden

param(
    [int]$CheckIntervalSeconds = 20,
    [switch]$Once,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$watchDir = Join-Path $root "data\watch"
if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Path $watchDir -Force | Out-Null }

$lockFile = Join-Path $watchDir "_watch_vibe_for_grok.lock"
$stateFile = Join-Path $watchDir "_watch_vibe_for_grok_state.json"

if ((Test-Path $lockFile) -and -not $Force) {
    $existing = Get-Content $lockFile -Raw | ConvertFrom-Json
    if ($existing.pid -and (Get-Process -Id $existing.pid -ErrorAction SilentlyContinue)) {
        Write-Host "[watch_vibe_for_grok] Already running pid=$($existing.pid). Use -Force to override." -ForegroundColor Yellow
        exit 1
    }
}
@{ pid = $PID; started = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json | Set-Content -Path $lockFile -Encoding UTF8
Write-Bot2BotLog -Component "watch_vibe_for_grok" -Message "Started pid=$PID interval=${CheckIntervalSeconds}s"

function Get-State {
    if (-not (Test-Path $stateFile)) {
        return [pscustomobject]@{ last_seen_vibe_msg_id = ""; last_poked_msg_id = "" }
    }
    return Get-Content $stateFile -Raw | ConvertFrom-Json
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 3 | Set-Content -Path $stateFile -Encoding UTF8
}

function Test-GrokAnswered {
    param($VibeMsg, $AllMessages)
    $vibeTs = [datetime]::Parse($VibeMsg.ts).ToUniversalTime()
    $grokReply = $AllMessages |
        Where-Object { $_.from -eq "grok" -and $_.to -eq "vibe" } |
        Where-Object {
            $ts = [datetime]::Parse($_.ts).ToUniversalTime()
            $ts -ge $vibeTs -and (
                $_.in_reply_to -eq $VibeMsg.id -or $ts -ge $vibeTs
            )
        } |
        Select-Object -First 1
    if (-not $grokReply) { return $false }
    $replyTs = [datetime]::Parse($grokReply.ts).ToUniversalTime()
    return ($replyTs -ge $vibeTs)
}

function Invoke-Check {
    param($State)

    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return $State }

    $messages = Get-Content $historyPath | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ }

    $latestVibe = $messages | Where-Object { $_.from -eq "vibe" -and $_.to -eq "grok" } | Select-Object -Last 1
    if (-not $latestVibe) { return $State }

    if ($latestVibe.id -eq $State.last_seen_vibe_msg_id) { return $State }
    $State.last_seen_vibe_msg_id = $latestVibe.id
    Save-State -State $State

    if (Test-GrokAnswered -VibeMsg $latestVibe -AllMessages $messages) {
        Write-Bot2BotLog -Component "watch_vibe_for_grok" -Message "New vibe msg $($latestVibe.id) already answered by grok — skip poke"
        return $State
    }

    if ($latestVibe.id -eq $State.last_poked_msg_id) { return $State }

    Write-Host "[watch_vibe_for_grok] New unanswered vibe -> grok: $($latestVibe.id) '$($latestVibe.subject)'" -ForegroundColor Cyan
    Write-Bot2BotLog -Component "watch_vibe_for_grok" -Message "Poking grok for vibe msg $($latestVibe.id) subject='$($latestVibe.subject)'"

    $pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
    try {
        & $pokeScript -AgentName grok | Out-Null
        $State.last_poked_msg_id = $latestVibe.id
        Save-State -State $State
    } catch {
        Write-Bot2BotLog -Component "watch_vibe_for_grok" -Message "Poke failed: $_" -Level "WARN"
    }

    return $State
}

try {
    do {
        try {
            $state = Get-State
            $state = Invoke-Check -State $state
        } catch {
            Write-Bot2BotLog -Component "watch_vibe_for_grok" -Message "Check loop error: $_" -Level "WARN"
        }
        if (-not $Once) { Start-Sleep -Seconds $CheckIntervalSeconds }
    } while (-not $Once)
} finally {
    if (Test-Path $lockFile) {
        $cur = Get-Content $lockFile -Raw | ConvertFrom-Json
        if ($cur.pid -eq $PID) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    }
    Write-Bot2BotLog -Component "watch_vibe_for_grok" -Message "Stopped pid=$PID"
}