# oobe_wizard.ps1 - Post-install OOBE (delegates to webagent oobe)
#
# NACH erfolgreichem Install ausfuehren:
#   cd bot2bot\scripts
#   .\oobe_wizard.ps1
#
# Nicht-interaktiv (Defaults: chatgpt,kimi,gemini):
#   .\oobe_wizard.ps1 -NonInteractive -SkipLogin

param(
    [string]$WebagentRoot = "",
    [string]$Brains = "",
    [switch]$NonInteractive,
    [switch]$SkipLogin
)

$ErrorActionPreference = "Stop"

if (-not $WebagentRoot) {
    $bot2botRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $WebagentRoot = Join-Path (Split-Path $bot2botRoot -Parent) "webagent"
}

$waBat = Join-Path $WebagentRoot "webagent.bat"
if (-not (Test-Path -LiteralPath $waBat)) {
    throw "webagent.bat nicht gefunden: $waBat"
}

$oobeArgs = @("oobe")
if ($Brains) {
    $oobeArgs += "--brains"
    $oobeArgs += $Brains
}
if ($NonInteractive) { $oobeArgs += "--yes" }
if ($SkipLogin) { $oobeArgs += "--skip-login" }

& $waBat @oobeArgs
exit $LASTEXITCODE