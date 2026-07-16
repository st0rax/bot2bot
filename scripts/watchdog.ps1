# watchdog.ps1
# Generic process watchdog for bot2bot-launched long-running jobs (e.g. calibration runs,
# battleroyale rounds). Detects unexpected process death (crash without a completion marker)
# and auto-restarts, without needing a human or Claude session to notice and intervene.
#
# Usage:
#   .\watchdog.ps1 -TrackFile ..\data\watch\live021r2.json -CheckIntervalSeconds 30 `
#     -GraceSeconds 60 -MaxRestarts 3 `
#     -RestartCommand 'C:\Users\storax\Desktop\webagent\venv\Scripts\python.exe' `
#     -RestartArgs 'scripts\run_leader_calibration.py --suite moderator-v1 --headed --timeout 300 --allow-live --post-inbox' `
#     -WorkingDirectory 'C:\Users\storax\Desktop\webagent'
#
# TrackFile is a small JSON state file the watchdog owns:
#   { "pid": 3664, "run_id": "live021r2", "output_json": "...\\live021r2.json",
#     "restarts": 0, "status": "running" }
#
# Completion detection: reads $OutputJson (if given) and checks payload.status == "complete".
# If the tracked PID disappears AND output is not "complete" AND restarts < MaxRestarts,
# the watchdog relaunches RestartCommand/RestartArgs, updates TrackFile with new PID, and
# posts a bot2bot alert message (append_message.ps1) so the incident is visible in history
# even if nobody is watching the terminal.
#
# Designed to run detached (Start-Process -WindowStyle Hidden) or as a Scheduled Task, so it
# survives independent of any single chat/agent session.

param(
    [Parameter(Mandatory)]
    [string]$TrackFile,

    [string]$OutputJson = "",

    [int]$CheckIntervalSeconds = 30,
    [int]$GraceSeconds = 60,
    [int]$MaxRestarts = 3,

    [string]$RestartCommand = "",
    [string]$RestartArgs = "",
    [string]$WorkingDirectory = "",

    [string]$AlertFrom = "watchdog",
    [string]$AlertTo = "claude",

    [switch]$Once
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

function Get-TrackState {
    if (-not (Test-Path $TrackFile)) {
        throw "TrackFile not found: $TrackFile"
    }
    return Get-Content $TrackFile -Raw | ConvertFrom-Json
}

function Set-TrackState {
    param($State)
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $TrackFile -Encoding UTF8
}

function Test-RunComplete {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $false }
    try {
        $payload = Get-Content $Path -Raw | ConvertFrom-Json
        return ($payload.status -eq "complete")
    } catch {
        return $false
    }
}

function Send-WatchdogAlert {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$Status = "info",
        [switch]$HumanAttention
    )
    $appendScript = Join-Path $PSScriptRoot "append_message.ps1"
    try {
        $alertArgs = @{
            From    = $AlertFrom
            To      = $AlertTo
            Subject = $Subject
            Body    = $Body
            Status  = $Status
            Poke    = $true
        }
        if ($HumanAttention) { $alertArgs.HumanAttention = $true }
        & $appendScript @alertArgs
    } catch {
        Write-Bot2BotLog -Component "watchdog" -Message "Failed to post alert: $_" -Level "WARN"
    }
}

function Start-Tracked {
    param($State)
    if (-not $RestartCommand) {
        throw "RestartCommand not set — cannot (re)start tracked process."
    }
    $procArgs = @{
        FilePath     = $RestartCommand
        ArgumentList = $RestartArgs
        PassThru     = $true
        WindowStyle  = "Hidden"
    }
    if ($WorkingDirectory) { $procArgs.WorkingDirectory = $WorkingDirectory }
    $proc = Start-Process @procArgs
    $State.pid = $proc.Id
    $State.status = "running"
    $State.restarts = [int]$State.restarts
    Set-TrackState -State $State
    Write-Bot2BotLog -Component "watchdog" -Message "(Re)started run_id=$($State.run_id) pid=$($proc.Id) restarts=$($State.restarts)"
    return $proc.Id
}

Write-Bot2BotLog -Component "watchdog" -Message "Watchdog started for TrackFile=$TrackFile"

do {
    Start-Sleep -Seconds $CheckIntervalSeconds
    $state = Get-TrackState
    $outJson = if ($OutputJson) { $OutputJson } elseif ($state.output_json) { $state.output_json } else { "" }

    if (Test-RunComplete -Path $outJson) {
        Write-Bot2BotLog -Component "watchdog" -Message "run_id=$($state.run_id) complete — watchdog exiting."
        $state.status = "complete"
        Set-TrackState -State $state
        break
    }

    $alive = $false
    if ($state.pid) {
        $proc = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
        $alive = [bool]$proc
    }

    if ($alive) {
        Write-Bot2BotLog -Component "watchdog" -Message "run_id=$($state.run_id) pid=$($state.pid) alive, no action."
        continue
    }

    # Process is gone but run isn't marked complete — grace period before declaring a crash,
    # in case the checkpoint write is still in flight.
    Start-Sleep -Seconds $GraceSeconds
    if (Test-RunComplete -Path $outJson) {
        Write-Bot2BotLog -Component "watchdog" -Message "run_id=$($state.run_id) completed during grace period — exiting."
        break
    }

    $restarts = [int]$state.restarts
    if ($restarts -ge $MaxRestarts) {
        $msg = "run_id=$($state.run_id): process gone, not complete, restarts=$restarts >= max=$MaxRestarts. Giving up — needs human/Claude look."
        Write-Bot2BotLog -Component "watchdog" -Message $msg -Level "ERROR"
        Send-WatchdogAlert -Subject "Watchdog: $($state.run_id) needs attention (max restarts hit)" `
            -Body "$msg`n`nOutputJson: $outJson`nTrackFile: $TrackFile" -Status "info" -HumanAttention
        $state.status = "failed_needs_attention"
        Set-TrackState -State $state
        break
    }

    Write-Bot2BotLog -Component "watchdog" -Message "run_id=$($state.run_id): pid=$($state.pid) gone, not complete. Restarting (attempt $($restarts+1)/$MaxRestarts)." -Level "WARN"
    $state.restarts = $restarts + 1
    $newPid = Start-Tracked -State $state
    Send-WatchdogAlert -Subject "Watchdog: $($state.run_id) auto-restarted (attempt $($state.restarts)/$MaxRestarts)" `
        -Body "Process pid=$($state.pid) disappeared without completion. Auto-restarted as pid=$newPid.`nOutputJson: $outJson" `
        -Status "info"

} while (-not $Once)
