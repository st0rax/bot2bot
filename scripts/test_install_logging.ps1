$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "install_logging.ps1")
$root = Join-Path $env:TEMP "wa_log_test_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $root -Force | Out-Null
$session = Start-InstallLog -Component "test" -Version "0.1.7" -InstallRoot $root
Write-Host "hello from test"
Complete-InstallLog -Session $session
if (-not (Test-Path $session.log_file)) { throw "log missing" }
Write-Host "OK log=$($session.log_file)"
exit 0