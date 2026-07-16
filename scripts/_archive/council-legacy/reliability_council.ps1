# reliability_council.ps1 — poll 7 webbrains on Claude reliability proposals
param(
    [string]$Brains = "",
    [double]$Timeout = 180,
    [switch]$Headed,
    [switch]$DryRun,
    [switch]$Post,
    [string]$InReplyTo = "8edfeaee-cc6a-4669-b887-d794e105c748"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagent = Join-Path (Split-Path $root -Parent) "webagent"
$python = Join-Path $webagent "venv\Scripts\python.exe"
$script = Join-Path $webagent "scripts\run_reliability_council.py"

if (-not (Test-Path $python)) { throw "Python not found: $python" }
if (-not (Test-Path $script)) { throw "run_reliability_council.py not found: $script" }

$args = @($script, "--timeout", $Timeout, "--in-reply-to", $InReplyTo)
if ($Brains) { $args += @("--brains", $Brains) }
if ($Headed) { $args += "--headed" }
if ($DryRun) { $args += "--dry-run" }
if ($Post) { $args += "--post" }

& $python @args
exit $LASTEXITCODE