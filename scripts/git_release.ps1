# git_release.ps1 — Release NUR via git/gh (kein Playwright-Browser)
#
#   .\git_release.ps1 -Version 0.1.3
#   .\git_release.ps1 -Version 0.1.3 -PushSource
#
# Einmalig: gh auth login  (oder .\gh_auth_wait.ps1)

param(
    [string]$Version = "0.1.10",
    [string]$Repo = "webagent",
    [switch]$SkipBuild,
    [switch]$SkipVerify,
    [switch]$PushSource
)

$ErrorActionPreference = "Stop"
$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root "dist"
$tag = "v$Version"
$assets = @(
    "webagent-suite_v$Version.zip",
    "install-webagent.ps1",
    "update-webagent.ps1",
    "ensure_prerequisites.ps1",
    "install_logging.ps1",
    "install_update.ps1",
    "install-webagent.cmd",
    "update-webagent.cmd"
)

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot "build_release_zip.ps1") -Version $Version
    if ($LASTEXITCODE -ne 0) { throw "build_release_zip failed" }
}

$desktop = [Environment]::GetFolderPath("Desktop")
Copy-Item (Join-Path $desktop "install-webagent.ps1") (Join-Path $dist "install-webagent.ps1") -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $desktop "update-webagent.ps1") (Join-Path $dist "update-webagent.ps1") -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $desktop "install-webagent.cmd") (Join-Path $dist "install-webagent.cmd") -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $desktop "update-webagent.cmd") (Join-Path $dist "update-webagent.cmd") -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $PSScriptRoot "ensure_prerequisites.ps1") (Join-Path $dist "ensure_prerequisites.ps1") -Force
Copy-Item (Join-Path $PSScriptRoot "install_logging.ps1") (Join-Path $dist "install_logging.ps1") -Force
Copy-Item (Join-Path $PSScriptRoot "install_update.ps1") (Join-Path $dist "install_update.ps1") -Force

if (-not $SkipVerify) {
    & (Join-Path $PSScriptRoot "pre_release_verify.ps1") -Version $Version -SkipInstall -SkipIex
    if ($LASTEXITCODE -ne 0) { throw "pre_release_verify FAILED — kein Upload" }
}

foreach ($a in $assets) {
    $p = Join-Path $dist $a
    if (-not (Test-Path $p)) { throw "Asset fehlt: $p" }
}

gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "gh CLI nicht eingeloggt. Einmalig: gh auth login --web  (danach nur noch git_release.ps1)"
}

$user = gh api user -q .login
$fullRepo = "$user/$Repo"
Write-Host "[git_release] gh CLI: $fullRepo $tag" -ForegroundColor Cyan

$assetPaths = $assets | ForEach-Object { Join-Path $dist $_ }
$notes = "WebAgent suite v$Version - install: irm .../install-webagent.ps1 | iex"

gh release view $tag -R $fullRepo 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    gh release create $tag @assetPaths -R $fullRepo --title $tag --notes $notes
} else {
    foreach ($ap in $assetPaths) {
        gh release upload $tag $ap -R $fullRepo --clobber
        if ($LASTEXITCODE -ne 0) { throw "upload failed: $ap" }
    }
}
if ($LASTEXITCODE -ne 0) { throw "gh release failed" }

$zipUrl = "https://github.com/$fullRepo/releases/download/$tag/webagent-suite_v$Version.zip"
$installUrl = "https://github.com/$fullRepo/releases/download/$tag/install-webagent.ps1"

Write-Host "[git_release] ZIP:      $zipUrl" -ForegroundColor Green
Write-Host "[git_release] Installer: $installUrl" -ForegroundColor Green

if ($PushSource) {
    & (Join-Path $PSScriptRoot "sync_git_monorepo.ps1") -Version $Version
    if ($LASTEXITCODE -ne 0) { throw "sync_git_monorepo failed" }
}

# Download-Sanity (GitHub CDN braucht oft ein paar Sekunden nach Upload)
$testZip = Join-Path $env:TEMP "wa_gh_release_test.zip"
$dlOk = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $testZip -UseBasicParsing -TimeoutSec 60
        $dlOk = $true
        break
    } catch {
        Write-Host "[git_release] Download attempt $i/6 failed, retry in ${i}0s ..." -ForegroundColor Yellow
        Start-Sleep -Seconds (10 * $i)
    }
}
if (-not $dlOk) { throw "Download-Test fehlgeschlagen: $zipUrl" }
Write-Host "[git_release] Download-Test OK ($([math]::Round((Get-Item $testZip).Length/1KB)) KB)" -ForegroundColor Green
Remove-Item $testZip -Force -ErrorAction SilentlyContinue

Write-Host "[git_release] DONE" -ForegroundColor Green