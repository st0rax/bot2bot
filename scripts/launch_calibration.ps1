# launch_calibration.ps1
# Start a live leader-calibration run with watchdog trackfile + auto-restart (--resume-from).
#
# Usage:
#   .\launch_calibration.ps1 -RunId live021r3
#   .\launch_calibration.ps1 -RunId live021r3 -NoWatchdog

param(
    [string]$RunId = "",
    [string]$Suite = "moderator-v1",
    [string]$ResumeFrom = "",
    [double]$Timeout = 300,
    [int]$MaxRestarts = 3,
    [switch]$Headed,
    [switch]$NoPostInbox,
    [switch]$NoWatchdog,
    [switch]$NoPersistTabs,
    [switch]$NoSharedBrowser
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagentRoot = Join-Path (Split-Path $root -Parent) "webagent"
$python = Join-Path $webagentRoot "venv\Scripts\python.exe"
$script = Join-Path $webagentRoot "scripts\run_leader_calibration.py"

if (-not (Test-Path $python)) { throw "Python not found: $python" }
if (-not (Test-Path $script)) { throw "Calibration script not found: $script" }

if (-not $RunId) {
    $RunId = "live" + (Get-Date).ToUniversalTime().ToString("MMddHHmm")
}

$watchDir = Join-Path $root "data\watch"
if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Path $watchDir -Force | Out-Null }

$outJson = Join-Path $webagentRoot "data\leader_calibration\runs\$RunId.json"
$trackFile = Join-Path $watchDir "$RunId.json"

# Refuse duplicate live runs for the same run_id (prevents resource conflicts).
$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'run_leader_calibration' -and $_.CommandLine -match "--run-id\s+$RunId" }
if ($existing) {
    $alive = @($existing | Where-Object {
        [bool](Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue)
    })
    if ($alive.Count -gt 0) {
        $pids = ($alive | ForEach-Object { $_.ProcessId }) -join ","
        throw "Calibration already running for run_id=$RunId (pids: $pids). Stop duplicates first or use -ResumeFrom."
    }
}

$pyArgs = @(
    "scripts\run_leader_calibration.py",
    "--suite", $Suite,
    "--timeout", $Timeout,
    "--allow-live",
    "--run-id", $RunId
)
if ($Headed) { $pyArgs += "--headed" }
if (-not $NoPostInbox) { $pyArgs += "--post-inbox" }
if ($ResumeFrom) { $pyArgs += @("--resume-from", $ResumeFrom) }

$resumeForWatchdog = if ($ResumeFrom) { $ResumeFrom } else { $RunId }

$pythonPath = Join-Path $webagentRoot "src"
$env:PYTHONPATH = $pythonPath
$env:WEBAGENT_USE_SHARED_BROWSER = if ($NoSharedBrowser) { "0" } else { "1" }
$env:WEBAGENT_PERSIST_TABS = if ($NoPersistTabs) { "0" } else { "1" }

$proc = Start-Process -FilePath $python -ArgumentList $pyArgs `
    -WorkingDirectory $webagentRoot -PassThru -WindowStyle Normal

# Track the python PID (not a short-lived pwsh wrapper).
$trackedPid = $proc.Id
Start-Sleep -Milliseconds 800
$child = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ParentProcessId -eq $proc.Id -and $_.Name -match '^python' } |
    Select-Object -First 1
if ($child) { $trackedPid = $child.ProcessId }

$track = [ordered]@{
    run_id      = $RunId
    output_json = $outJson
    pid         = $trackedPid
    status      = "running"
    restarts    = 0
    restart_command = $python
    restart_args = (
        "scripts\run_leader_calibration.py --suite $Suite --timeout $Timeout " +
        "--allow-live --run-id $RunId --resume-from $resumeForWatchdog" +
        $(if ($Headed) { " --headed" } else { "" }) +
        $(if (-not $NoPostInbox) { " --post-inbox" } else { "" })
    )
    working_directory = $webagentRoot
}
$track | ConvertTo-Json -Depth 4 | Set-Content -Path $trackFile -Encoding UTF8

Write-Host "[launch_calibration] run_id=$RunId pid=$trackedPid" -ForegroundColor Green
Write-Host "  track:  $trackFile" -ForegroundColor DarkGray
Write-Host "  output: $outJson" -ForegroundColor DarkGray

if (-not $NoWatchdog) {
    $watchdog = Join-Path $PSScriptRoot "watchdog.ps1"
    $wdArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $watchdog,
        "-TrackFile", $trackFile,
        "-OutputJson", $outJson,
        "-MaxRestarts", $MaxRestarts,
        "-RestartCommand", $python,
        "-RestartArgs", $track.restart_args,
        "-WorkingDirectory", $webagentRoot
    )
    Start-Process -FilePath "pwsh" -ArgumentList $wdArgs -WindowStyle Hidden
    Write-Host "[launch_calibration] per-run watchdog started" -ForegroundColor DarkGray
}

Write-Output ([pscustomobject]@{
    run_id = $RunId
    pid    = $trackedPid
    track  = $trackFile
    output = $outJson
})