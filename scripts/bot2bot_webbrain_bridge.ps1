# bot2bot_webbrain_bridge.ps1
# Connectivity relay only — not for PROPOSED_DIFF approval (Claude Desktop only).
#
# Usage:
#   .\bot2bot_webbrain_bridge.ps1 -AgentName chatgpt
#   .\bot2bot_webbrain_bridge.ps1 -AgentName kimi -DryRun
#   .\bot2bot_webbrain_bridge.ps1 -AgentName chatgpt -Headed

param(
    [Parameter(Mandatory)]
    [string]$AgentName,

    [string]$Root = "",
    [switch]$DryRun,
    [switch]$Headed,
    [switch]$NoPoke,
    [double]$Timeout = 300
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$bot2botRoot = if ($Root) { (Resolve-Path $Root).Path } else { Get-Bot2BotRoot }
$webagentRoot = (Resolve-Path (Join-Path $bot2botRoot "..\webagent")).Path
$webagentRs = Join-Path $webagentRoot "webagent-rs\target\release\webagent.exe"
if (-not (Test-Path $webagentRs)) {
    $webagentRs = Join-Path $webagentRoot "webagent-rs\target\debug\webagent.exe"
}
$profile = Join-Path $webagentRoot "data\profiles\shared"
if (Test-Path $profile) {
    $env:WEBAGENT_PROFILE_DIR = $profile
}
$env:WEBAGENT_USE_SHARED_BROWSER = "1"
$env:WEBAGENT_PERSIST_TABS = "1"
if ($webagentRs -and (Test-Path $webagentRs)) {
    $env:WEBAGENT_RS_BIN = $webagentRs
}

$python = Join-Path $webagentRoot "venv\Scripts\python.exe"
$script = Join-Path $webagentRoot "scripts\bot2bot_webbrain_bridge.py"

if (-not (Test-Path $python)) {
    throw "webagent venv python not found: $python"
}
if (-not (Test-Path $script)) {
    throw "bridge script not found: $script"
}

$env:PYTHONPATH = Join-Path $webagentRoot "src"
$pyArgs = @(
    $script,
    "--agent", $AgentName,
    "--bot2bot-root", $bot2botRoot
)
if ($DryRun) { $pyArgs += "--dry-run" }
if ($Headed) { $pyArgs += "--headed" }
if ($NoPoke) { $pyArgs += "--no-poke" }
if ($Timeout -gt 0) { $pyArgs += @("--timeout", $Timeout) }

& $python @pyArgs
exit $LASTEXITCODE