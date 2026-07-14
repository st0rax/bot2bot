# Thin wrapper — canonical implementation in webagent/delivery/
$target = Join-Path $env:USERPROFILE "Desktop\webagent\delivery\grok_notify_storax.ps1"
if (-not (Test-Path $target)) { throw "missing $target" }
& powershell -NoProfile -ExecutionPolicy Bypass -File $target @args
exit $LASTEXITCODE