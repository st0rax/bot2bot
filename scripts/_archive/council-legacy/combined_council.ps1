# combined_council.ps1 — 98db941d Mehrheitsabstimmung Reliability + INT-003
param(
    [double]$Timeout = 120,
    [switch]$Headed,
    [switch]$Post
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")
$webagent = Join-Path (Split-Path (Get-Bot2BotRoot) -Parent) "webagent"
$python = Join-Path $webagent "venv\Scripts\python.exe"
$script = Join-Path $webagent "scripts\run_combined_council.py"
if (-not $env:WEBAGENT_USE_SHARED_BROWSER) {
    $env:WEBAGENT_USE_SHARED_BROWSER = "0"
}
$env:WEBAGENT_PERSIST_TABS = "0"
$args = @($script, "--timeout", $Timeout)
if ($Headed) { $args += "--headed" }
if ($Post) { $args += "--post" }
& $python @args
exit $LASTEXITCODE