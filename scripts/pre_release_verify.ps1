# pre_release_verify.ps1 — Pflicht vor Release-Upload (URLs + Smoke-Install)
#
#   .\pre_release_verify.ps1
#   .\pre_release_verify.ps1 -Version 0.1.3 -SkipInstall

param(
    [string]$Version = "0.1.10",
    [string]$Repo = "alexanderkrenz89-ctrl/webagent",
    [switch]$SkipInstall,
    [switch]$SkipIex,
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"
$base = "https://github.com/$Repo/releases/download/v$Version"
$assets = @(
    "install-webagent.ps1",
    "update-webagent.ps1",
    "ensure_prerequisites.ps1",
    "install_logging.ps1",
    "install_update.ps1",
    "webagent-suite_v$Version.zip"
)

Write-Host "=== pre_release_verify v$Version ===" -ForegroundColor Cyan

# 1) URL checks (lokal gebaut ODER bereits live)
$dist = Join-Path (Split-Path $PSScriptRoot -Parent) "dist"
foreach ($a in $assets) {
    $local = Join-Path $dist $a
    if (-not (Test-Path $local)) { throw "Lokal fehlt: $local" }
    $live = "$base/$a"
    try {
        $r = Invoke-WebRequest -Uri $live -Method Head -UseBasicParsing -TimeoutSec 30
        Write-Host "[OK] live $a ($($r.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] live nicht erreichbar (Upload noch noetig?): $a" -ForegroundColor Yellow
    }
}

# 2) Script-Syntax (Parser) + ASCII-only (kein Em-Dash/UTF8-Murks auf fremden PCs)
$distScripts = @(
    @{ Dir = $dist; Names = @("install-webagent.ps1", "update-webagent.ps1", "ensure_prerequisites.ps1", "install_logging.ps1", "install_update.ps1") },
    @{ Dir = $PSScriptRoot; Names = @("install_logging.ps1", "install_update.ps1") },
    @{ Dir = $PSScriptRoot; Names = @("oobe_wizard.ps1", "first_login_wizard.ps1", "install_webagent.ps1") }
)
foreach ($group in $distScripts) {
foreach ($scriptName in $group.Names) {
    $scriptPath = Join-Path $group.Dir $scriptName
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) {
        $parseErrors | ForEach-Object { Write-Host "[FAIL] $scriptName $_" -ForegroundColor Red }
        throw "$scriptName Parser-Fehler"
    }
    $text = [System.IO.File]::ReadAllText($scriptPath)
    if ($text -match '[^\x00-\x7F]') {
        throw "$scriptName enthaelt Nicht-ASCII Zeichen (Em-Dash/Umlaut) - nur ASCII erlaubt"
    }
    Write-Host "[OK] $scriptName syntax + ASCII" -ForegroundColor Green
}
}

$ps51 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$oobeTest = Join-Path $PSScriptRoot "test_oobe_ps51.ps1"
& $ps51 -NoProfile -ExecutionPolicy Bypass -File $oobeTest
if ($LASTEXITCODE -ne 0) { throw "test_oobe_ps51 failed" }
Write-Host "[OK] OOBE PS5.1 unit tests" -ForegroundColor Green

# 3) irm simulation (live wenn vorhanden, sonst lokales dist)
$localInstaller = Join-Path $dist "install-webagent.ps1"
$script = $null
try {
    $script = Invoke-RestMethod -Uri "$base/install-webagent.ps1" -TimeoutSec 120
    Write-Host "[OK] irm live download ($($script.Length) chars)" -ForegroundColor Green
} catch {
    $script = [System.IO.File]::ReadAllText($localInstaller)
    Write-Host "[OK] irm local dist ($($script.Length) chars, live noch nicht da)" -ForegroundColor Green
}
if ($script.Length -lt 1000) { throw "irm: Script zu kurz" }
if ($script -notmatch 'Ensure-InstallPrerequisites') { throw "irm: Scriptinhalt unplausibel" }
if ($script -notmatch 'Resolve-Pwsh7') { throw "irm: PS5.1 bootstrap fehlt (Resolve-Pwsh7)" }

# 3a) ZIP sanity
$zipPath = Join-Path $dist "webagent-suite_v$Version.zip"
$releaseReg = Join-Path (Split-Path $PSScriptRoot -Parent) "agents\registry.release.json"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $bad = @($zip.Entries | Where-Object { $_.FullName -match 'git-publish/' })
    if ($bad.Count -gt 0) { throw "ZIP enthaelt git-publish/ ($($bad.Count) entries)" }
    $regEntry = $zip.Entries | Where-Object { $_.FullName -eq 'bot2bot/agents/registry.json' } | Select-Object -First 1
    if (-not $regEntry) { throw "ZIP: bot2bot/agents/registry.json fehlt" }
    $installEntry = $zip.Entries | Where-Object { $_.FullName -eq 'INSTALL.ps1' } | Select-Object -First 1
    if (-not $installEntry) { throw "ZIP: INSTALL.ps1 fehlt" }
    $sr = New-Object System.IO.StreamReader($installEntry.Open())
    $installText = $sr.ReadToEnd()
    $sr.Dispose()
    if ($installText -match '[^\x00-\x7F]') { throw "ZIP: INSTALL.ps1 enthaelt Nicht-ASCII" }
    if ($installText -notmatch 'InstallRoot') { throw "ZIP: INSTALL.ps1 fehlt InstallRoot (pwd-Install)" }
    if ($installText -notmatch 'scripts refreshed') { throw "ZIP: INSTALL.ps1 fehlt Script-Force-Update" }
    $updateEntry = $zip.Entries | Where-Object { $_.FullName -eq 'UPDATE.ps1' } | Select-Object -First 1
    if (-not $updateEntry) { throw "ZIP: UPDATE.ps1 fehlt" }
    $usr = New-Object System.IO.StreamReader($updateEntry.Open())
    $updateText = $usr.ReadToEnd()
    $usr.Dispose()
    if ($updateText -match '[^\x00-\x7F]') { throw "ZIP: UPDATE.ps1 enthaelt Nicht-ASCII" }
    if ($updateText -notmatch 'Invoke-WebAgentSuiteUpdate') { throw "ZIP: UPDATE.ps1 fehlt update logic" }
    $updScriptEntry = $zip.Entries | Where-Object { $_.FullName -eq 'bot2bot/scripts/install_update.ps1' } | Select-Object -First 1
    if (-not $updScriptEntry) { throw "ZIP: bot2bot/scripts/install_update.ps1 fehlt" }
    $waUpdateEntry = $zip.Entries | Where-Object { $_.FullName -eq 'webagent/update-webagent.ps1' } | Select-Object -First 1
    if (-not $waUpdateEntry) { throw "ZIP: webagent/update-webagent.ps1 fehlt" }
    $waInstallerEntry = $zip.Entries | Where-Object { $_.FullName -eq 'webagent/install-webagent.ps1' } | Select-Object -First 1
    if (-not $waInstallerEntry) { throw "ZIP: webagent/install-webagent.ps1 fehlt" }
    $wis = $waInstallerEntry.Open()
    $wir = New-Object System.IO.StreamReader($wis)
    $waInstallerText = $wir.ReadToEnd()
    $wir.Dispose()
    $wis.Dispose()
    if ($waInstallerText -notmatch "v$Version") { throw "ZIP: webagent/install-webagent.ps1 Version != v$Version" }
    if ($waInstallerText -notmatch 'InstallRoot') { throw "ZIP: webagent/install-webagent.ps1 fehlt InstallRoot" }
    if ($waInstallerText -notmatch 'Register-InstallLoggingFallback') { throw "ZIP: install-webagent.ps1 fehlt Start-InstallLog fix" }
    $oobeEntry = $zip.Entries | Where-Object { $_.FullName -eq 'bot2bot/scripts/oobe_wizard.ps1' } | Select-Object -First 1
    if (-not $oobeEntry) { throw "ZIP: bot2bot/scripts/oobe_wizard.ps1 fehlt" }
    $os = $oobeEntry.Open()
    $or = New-Object System.IO.StreamReader($os)
    $oobeText = $or.ReadToEnd()
    $or.Dispose()
    $os.Dispose()
    if ($oobeText -match 'Schritt 1/2 - Web-Brains') { throw "ZIP: oobe_wizard.ps1 nutzt altes 8x-Read-Host UI" }
    if ($oobeText -notmatch 'webagent\.bat') { throw "ZIP: oobe_wizard.ps1 fehlt webagent.bat delegation" }
    if ($oobeText -notmatch '"oobe"') { throw "ZIP: oobe_wizard.ps1 fehlt webagent oobe delegation" }
    $oobePy = $zip.Entries | Where-Object { $_.FullName -eq 'webagent/src/webagent/oobe.py' } | Select-Object -First 1
    if (-not $oobePy) { throw "ZIP: webagent/src/webagent/oobe.py fehlt" }
    if (Test-Path $releaseReg) {
        $expected = Get-Content $releaseReg -Raw
        $zs = $regEntry.Open()
        $zr = New-Object System.IO.StreamReader($zs)
        $actual = $zr.ReadToEnd()
        $zr.Dispose()
        $zs.Dispose()
        if ($expected.Trim() -ne $actual.Trim()) { throw "ZIP: registry.json != registry.release.json" }
    }
    Write-Host "[OK] ZIP sanity (no git-publish, registry, INSTALL.ps1 ASCII)" -ForegroundColor Green
} finally {
    $zip.Dispose()
}

# 3b) Real iex under Windows PowerShell 5.1 (fresh PC default shell)
if ($SkipIex) {
    Write-Host "[SKIP] iex PS5.1 smoke (-SkipIex)" -ForegroundColor Yellow
} else {
Write-Host "[..] iex PS5.1 smoke dauert ~1-2 Min (Playwright uebersprungen)" -ForegroundColor Cyan
$iexRoot = Join-Path $env:TEMP "wa_iex_ps51_$(Get-Date -Format 'yyyyMMddHHmmss')"
if (Test-Path $iexRoot) { Remove-Item $iexRoot -Recurse -Force }
New-Item -ItemType Directory -Path $iexRoot -Force | Out-Null

$iexScript = Join-Path $PSScriptRoot "test_iex_bootstrap.ps1"
$ps51 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $ps51)) { throw "Windows PowerShell 5.1 nicht gefunden: $ps51" }

Write-Host "[..] iex PS5.1 smoke (local dist, InstallRoot: $iexRoot)" -ForegroundColor Cyan
& $ps51 -NoProfile -ExecutionPolicy Bypass -File $iexScript -Version $Version -LocalScript $localInstaller -InstallRoot $iexRoot -NonInteractive
if ($LASTEXITCODE -ne 0) { throw "iex PS5.1 smoke exit $LASTEXITCODE" }

$iexManifest = Join-Path $iexRoot "bot2bot\data\install_manifest.json"
if (-not (Test-Path $iexManifest)) { throw "iex PS5.1: install_manifest.json fehlt" }
Write-Host "[OK] iex PS5.1 smoke install" -ForegroundColor Green
Remove-Item $iexRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($SkipInstall) {
    Write-Host "=== pre_release_verify PASSED (skip pwsh -File install) ===" -ForegroundColor Green
    exit 0
}

# 4) Smoke-Install von live URL
if (-not $InstallRoot) {
    $InstallRoot = Join-Path $env:TEMP "wa_pre_release_smoke"
}
if (Test-Path $InstallRoot) { Remove-Item $InstallRoot -Recurse -Force }
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

$tmpScript = Join-Path $env:TEMP "install-webagent_verify.ps1"
$liveOk = $false
try {
    Invoke-WebRequest -Uri "$base/install-webagent.ps1" -OutFile $tmpScript -UseBasicParsing -TimeoutSec 30
    $liveOk = $true
} catch {
    Copy-Item -LiteralPath $localInstaller -Destination $tmpScript -Force
    $env:WA_INSTALL_LOCAL_ZIP = Join-Path $dist "webagent-suite_v$Version.zip"
    Write-Host "[..] live installer fehlt - nutze lokales dist" -ForegroundColor Yellow
}
& pwsh -NoProfile -ExecutionPolicy Bypass -File $tmpScript -InstallRoot $InstallRoot -NonInteractive
if (-not $liveOk) { Remove-Item Env:WA_INSTALL_LOCAL_ZIP -ErrorAction SilentlyContinue }
if ($LASTEXITCODE -ne 0) { throw "Smoke-Install exit $LASTEXITCODE" }

$manifest = Join-Path $InstallRoot "bot2bot\data\install_manifest.json"
if (-not (Test-Path $manifest)) { throw "install_manifest.json fehlt" }
Write-Host "=== pre_release_verify PASSED ===" -ForegroundColor Green