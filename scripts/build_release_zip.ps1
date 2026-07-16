# build_release_zip.ps1 — Lean ZIP fuer Online-Distribution
#
#   .\build_release_zip.ps1
#   .\build_release_zip.ps1 -Version 0.1.0

param(
    [string]$Version = "0.1.1",
    [string]$OutputZip = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$dist = Join-Path $root "dist"
$staging = Join-Path $dist "webagent-suite_staging"
$zipName = "webagent-suite_v$Version.zip"

if (-not $OutputZip) {
    $OutputZip = Join-Path $dist $zipName
}
New-Item -ItemType Directory -Path $dist -Force | Out-Null

& (Join-Path $PSScriptRoot "package_release.ps1") -OutputDir $staging

if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputZip -CompressionLevel Optimal
Remove-Item $staging -Recurse -Force

$mb = [math]::Round((Get-Item $OutputZip).Length / 1MB, 2)
$hash = (Get-FileHash $OutputZip -Algorithm SHA256).Hash

$manifest = @{
    version = $Version
    built_at = (Get-Date).ToUniversalTime().ToString("o")
    zip = $zipName
    size_mb = $mb
    sha256 = $hash
    release_url_template = "https://github.com/STORAX_USER/webagent/releases/download/v$Version/$zipName"
} | ConvertTo-Json -Depth 3
$manifest | Set-Content (Join-Path $dist "release_manifest.json") -Encoding UTF8

Write-Host "[build_release_zip] $OutputZip ($mb MB)" -ForegroundColor Green
Write-Host "[build_release_zip] sha256=$hash"
Write-Output $OutputZip
exit 0