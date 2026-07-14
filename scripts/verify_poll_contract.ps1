# verify_poll_contract.ps1 — Atomic poll contract verification (shim + task + exit 0).
param(
    [switch]$SkipInstall,
    [string]$ScratchDir = $(Join-Path $env:TEMP "grok-goal-f29811d96432\implementer")
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
$logFile = Join-Path $ScratchDir "bot2bot-poll.log"

function Write-Log([string]$Msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

$shim = Join-Path $PSScriptRoot "poll_grok_inbox.ps1"
$installer = Join-Path $PSScriptRoot "install_grok_inbox_poll_task.ps1"
$contractNeedle = "bot2bot\scripts\poll_grok_inbox.ps1"

"=== verify_poll_contract $(Get-Date -Format o) ===" | Set-Content $logFile -Encoding UTF8
Write-Log "shim=$shim"
Write-Log "log=$logFile"

if (-not (Test-Path $shim)) {
    Write-Log "FAIL: shim missing"
    exit 1
}
Write-Log "OK: shim exists"

Write-Log "--- poll shim run ---"
& $shim 2>&1 | ForEach-Object { Write-Log "poll: $_" }
$pollExit = $LASTEXITCODE
Write-Log "POLL_EXIT_CODE=$pollExit"
if ($pollExit -ne 0) {
    Write-Log "FAIL: poll exit $pollExit"
    exit 1
}

function Test-TaskContract {
    $task = Get-ScheduledTask -TaskName "GrokInboxPoll" -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Log "TASK: missing"
        return $false
    }
    $args = ($task.Actions | Select-Object -First 1).Arguments
    Write-Log "TASK_STATE=$($task.State)"
    Write-Log "TASK_EXECUTE=$($task.Actions.Execute)"
    Write-Log "TASK_ARGUMENTS=$args"
    if ($args -match [regex]::Escape($contractNeedle)) {
        Write-Log "OK: task arguments contain $contractNeedle"
        return $true
    }
    Write-Log "FAIL: task arguments do not contain $contractNeedle"
    return $false
}

Write-Log "--- scheduled task (before install) ---"
$ok = Test-TaskContract

if (-not $ok -and -not $SkipInstall) {
    Write-Log "--- attempting install (admin) ---"
    try {
        $installLog = Join-Path $ScratchDir "grok-task-install.log"
        Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-Command", "& '$installer' *>&1 | Tee-Object '$installLog'"
        ) | Out-Null
        if (Test-Path $installLog) {
            Get-Content $installLog | ForEach-Object { Write-Log "install: $_" }
        }
    } catch {
        Write-Log "install error: $_"
    }
    Write-Log "--- scheduled task (after install) ---"
    $ok = Test-TaskContract
}

if (-not $ok) {
    Write-Log "CONTRACT=FAIL"
    exit 1
}

Write-Log "CONTRACT=PASS"
exit 0