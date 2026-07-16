# p5_council.ps1 — P5 Urteils-Gate + INTEGRITY poll (7 webbrains)
param(
    [double]$Timeout = 120,
    [switch]$Headed,
    [switch]$Post
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")
$webagent = Join-Path (Split-Path (Get-Bot2BotRoot) -Parent) "webagent"
$python = Join-Path $webagent "venv\Scripts\python.exe"
$script = Join-Path $webagent "scripts\run_p5_council.py"
if (-not $env:WEBAGENT_USE_SHARED_BROWSER) { $env:WEBAGENT_USE_SHARED_BROWSER = "0" }
$env:WEBAGENT_PERSIST_TABS = "0"
$args = @($script, "--timeout", $Timeout)
if ($Headed) { $args += "--headed" }
if ($Post) { $args += "--post" }
& $python @args
exit $LASTEXITCODE