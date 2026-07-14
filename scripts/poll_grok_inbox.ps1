# poll_grok_inbox.ps1 — ScheduledTask entrypoint shim (contract path).
# Implementation lives in webagent/delivery/poll_grok_inbox.ps1.
$ErrorActionPreference = "Stop"

$webagentRoot = if ($env:WEBAGENT_ROOT) {
    $env:WEBAGENT_ROOT
} else {
    Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "webagent"
}
$impl = Join-Path $webagentRoot "delivery\poll_grok_inbox.ps1"

if (-not (Test-Path $impl)) {
    Write-Error "Missing implementation: $impl (set WEBAGENT_ROOT or install webagent delivery scripts)"
    exit 1
}

& $impl @args
exit $LASTEXITCODE