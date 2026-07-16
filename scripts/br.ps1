# br.ps1 — Battleroyale (/br) entry point
#
# Usage:
#   .\br.ps1                          # default moderator/leader topic
#   .\br.ps1 -Headed -RetryOnEmpty    # live poll with visible browser
#   .\br.ps1 -Topic "Custom question" -Title "Custom BR title"
#   .\br.ps1 -DryRun                  # format only, no relay

param(
    [string]$Topic = "",
    [string]$Title = "",
    [string]$RunId = "",
    [switch]$Headed,
    [double]$Timeout = 300,
    [switch]$RetryOnEmpty,
    [switch]$DryRun,
    [switch]$NoInbox
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagentSrc = Join-Path (Split-Path $root -Parent) "webagent\src"
$brPy = Join-Path $PSScriptRoot "br.py"

if (-not (Test-Path $brPy)) {
    throw "br.py not found: $brPy"
}

$env:PYTHONPATH = $webagentSrc
if (-not $env:WEBAGENT_USE_SHARED_BROWSER) {
    $env:WEBAGENT_USE_SHARED_BROWSER = "1"
}
if (-not $env:WEBAGENT_PERSIST_TABS) {
    $env:WEBAGENT_PERSIST_TABS = "1"
}

$python = Join-Path (Split-Path $root -Parent) "webagent\venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    $python = "python"
}

$argsList = @($brPy)
if ($Topic) { $argsList += @("--topic", $Topic) }
if ($Title) { $argsList += @("--title", $Title) }
if ($RunId) { $argsList += @("--run-id", $RunId) }
if ($Headed) { $argsList += "--headed" }
$argsList += @("--timeout", $Timeout)
if ($RetryOnEmpty) { $argsList += "--retry-on-empty" }
if ($DryRun) { $argsList += "--dry-run" }
if ($NoInbox) { $argsList += "--no-inbox" }

Write-Host "[br] Battleroyale start" -ForegroundColor Cyan
& $python @argsList
exit $LASTEXITCODE