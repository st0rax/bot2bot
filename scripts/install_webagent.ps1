# install_webagent.ps1 - Hauptinstaller (bot2bot + webagent)
#
#   .\install_webagent.ps1
#   .\install_webagent.ps1 -TargetDir C:\Users\storax\Desktop\webagent -NonInteractive
#   .\install_webagent.ps1 -Bot2BotDir C:\path\bot2bot -SourceWebagent C:\path\webagent

param(
    [string]$TargetDir = "",
    [string]$Bot2BotDir = "",
    [string]$SourceWebagent = "",
    [string]$PythonExe = "python",
    [switch]$SkipOobe,
    [switch]$SkipPlaywright,
    [switch]$NonInteractive,
    [switch]$FullVerify,
    [switch]$SkipInstallLog,
    [switch]$Update,
    [switch]$FullUpdate,
    [string]$SuiteVersion = "0.1.10"
)

$ErrorActionPreference = "Stop"
if (-not $SkipPlaywright -and $env:WA_INSTALL_SKIP_PLAYWRIGHT -eq "1") { $SkipPlaywright = $true }
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")
. (Join-Path $PSScriptRoot "install_logging.ps1")

$script:Bot2BotRoot = if ($Bot2BotDir) {
    [System.IO.Path]::GetFullPath($Bot2BotDir)
} else {
    Get-Bot2BotRoot
}
$installRoot = Split-Path $script:Bot2BotRoot -Parent

if (-not $TargetDir) {
    if ($NonInteractive) {
        $TargetDir = Join-Path $installRoot "webagent"
    } else {
        $default = Join-Path $installRoot "webagent"
        $raw = Read-Host "Webagent-Zielpfad (Enter=$default)"
        $TargetDir = if ([string]::IsNullOrWhiteSpace($raw)) { $default } else { $raw }
    }
}
$TargetDir = [System.IO.Path]::GetFullPath($TargetDir)

if (-not $SourceWebagent) {
    $SourceWebagent = Join-Path (Split-Path $script:Bot2BotRoot -Parent) "webagent"
}

if ($Update -and -not $PSBoundParameters.ContainsKey('SkipPlaywright') -and -not $FullUpdate) {
    $SkipPlaywright = $true
}

$logComponent = if ($Update) { "install_webagent_update" } else { "install_webagent" }
$installLog = $null
if (-not $SkipInstallLog) {
    $installLog = Start-InstallLog -Component $logComponent -Version $SuiteVersion -InstallRoot $installRoot -Bot2BotRoot $script:Bot2BotRoot
}

try {
Write-Host ""
Write-Host "=== install_webagent$(if ($Update) { ' (UPDATE)' }) ===" -ForegroundColor Cyan
Write-Host "bot2bot:  $script:Bot2BotRoot"
Write-Host "source:   $SourceWebagent"
Write-Host "target:   $TargetDir"
if ($installLog) { Write-Host "log:      $($installLog.log_file)" -ForegroundColor DarkCyan }
Write-Host ""

# Python 3.11+ (auto-install via winget/python.org wenn noetig)
. (Join-Path $PSScriptRoot "ensure_prerequisites.ps1")
$pyInfo = Ensure-InstallPrerequisites -NonInteractive:$NonInteractive -PythonExe $PythonExe
$PythonExe = $pyInfo.Exe
$pyVersion = $pyInfo.Version
Write-Host "[OK] Python $pyVersion ($PythonExe)" -ForegroundColor Green

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Host "[install] Verzeichnis erstellt: $TargetDir"
}

$srcResolved = $null
if (Test-Path (Join-Path $SourceWebagent "pyproject.toml")) {
    $srcResolved = (Resolve-Path $SourceWebagent).Path
}
$dstResolved = (Resolve-Path $TargetDir).Path

if ($srcResolved -and $srcResolved -ne $dstResolved -and -not $Update) {
    Write-Host "[install] Kopiere webagent ..."
    $rcArgs = @(
        $srcResolved, $dstResolved, "/E",
        "/XD", "venv", ".git", "__pycache__", "runs", ".pytest_cache",
        "runtime", "terminals", "_archive", "logs", "shared",
        "/XF", "debug_*.png", "automation.log", "install_bot2bot_root.txt",
        "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np"
    )
    robocopy @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed exit $LASTEXITCODE" }
}

# venv + deps
$venvPy = Join-Path $TargetDir "venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Write-Host "[install] Erstelle venv ..."
    & $PythonExe -m venv (Join-Path $TargetDir "venv")
    if ($LASTEXITCODE -ne 0) { throw "venv creation failed" }
}
Write-Host "[install] pip install -e ."
& $venvPy -m pip install -q --upgrade pip
& $venvPy -m pip install -q -e $TargetDir
if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
$req = Join-Path $TargetDir "requirements.txt"
if (Test-Path $req) {
    Write-Host "[install] pip install -r requirements.txt (dev/test extras)"
    & $venvPy -m pip install -q -r $req
    if ($LASTEXITCODE -ne 0) { throw "requirements.txt install failed" }
}

# Playwright Chromium
if (-not $SkipPlaywright) {
    Write-Host "[install] Playwright Chromium ..."
    $env:PYTHONPATH = Join-Path $TargetDir "src"
    & $venvPy (Join-Path $TargetDir "src\bootstrap.py")
    if ($LASTEXITCODE -ne 0) { throw "bootstrap/playwright failed" }
}

# Empty shared scaffold (robocopy excludes populated shared/)
$sharedScaffold = Join-Path $TargetDir "data\profiles\shared"
if (-not (Test-Path $sharedScaffold)) {
    New-Item -ItemType Directory -Path $sharedScaffold -Force | Out-Null
    Set-Content (Join-Path $sharedScaffold ".gitkeep") "" -Encoding ASCII
}

# Shared profile bootstrap (Option2)
$migrate = Join-Path $TargetDir "scripts\migrate_option2_profile.ps1"
if (Test-Path $migrate) {
    Write-Host "[install] Option2 shared profile ..."
    & $migrate
}

# Env flags in batch files
foreach ($bat in @("start.bat", "webagent.bat")) {
    $batPath = Join-Path $TargetDir $bat
    if (-not (Test-Path $batPath)) { continue }
    $content = Get-Content $batPath -Raw
    if ($content -notmatch "WEBAGENT_USE_SHARED_BROWSER") {
        $content = $content -replace "(set PYTHONPATH=.*\r?\n)", "`$1set WEBAGENT_USE_SHARED_BROWSER=1`r`n"
        Set-Content $batPath $content -Encoding ASCII -NoNewline
    }
}

# bot2bot link for webagent
$linkPath = Join-Path $TargetDir "data\install_bot2bot_root.txt"
Set-Content $linkPath $script:Bot2BotRoot -Encoding UTF8 -NoNewline

# Ensure bot2bot dirs
foreach ($sub in @("history", "inbox", "data\watch", "agents")) {
    $p = Join-Path $script:Bot2BotRoot $sub
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
$hist = Join-Path $script:Bot2BotRoot "history\conversation.jsonl"
if (-not (Test-Path $hist)) { New-Item -ItemType File -Path $hist -Force | Out-Null }

# OOBE laeuft separat NACH technischem Install (Brains waehlen + Login)
#   cd $script:Bot2BotRoot\scripts; .\oobe_wizard.ps1

# Manifest (before verify - verify checks this file)
$manifestPath = Join-Path $script:Bot2BotRoot "data\install_manifest.json"
$prevManifest = $null
if ($Update -and (Test-Path -LiteralPath $manifestPath)) {
    try { $prevManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch { }
}
$installedAt = if ($prevManifest -and $prevManifest.installed_at) {
    [string]$prevManifest.installed_at
} else {
    (Get-Date).ToUniversalTime().ToString("o")
}
$manifest = @{
    installed_at  = $installedAt
    python        = $pyVersion.Trim()
    bot2bot_root  = $script:Bot2BotRoot
    webagent_root = $TargetDir
    shared_browser = $true
    playwright    = (-not $SkipPlaywright)
    verify        = "pending"
    suite_version = $SuiteVersion
}
if ($Update) {
    $manifest.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $manifest.mode = "update"
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content $manifestPath -Encoding UTF8

# Verify
$verifyArgs = @{ WebagentRoot = $TargetDir; Bot2BotRoot = $script:Bot2BotRoot }
if ($FullVerify) { $verifyArgs.Full = $true }
& (Join-Path $PSScriptRoot "verify_install.ps1") @verifyArgs
if ($LASTEXITCODE -ne 0) { throw "verify_install failed" }
$manifest.verify = "passed"
$manifest | ConvertTo-Json -Depth 4 | Set-Content $manifestPath -Encoding UTF8

if ($installLog) { Complete-InstallLog -Session $installLog }

Write-Host ""
if ($Update) {
    Write-Host "Update abgeschlossen (v$SuiteVersion)." -ForegroundColor Green
} else {
    Write-Host "Installation abgeschlossen." -ForegroundColor Green
}
Write-Host "Manifest: $manifestPath"
if ($installLog) { Write-Host "Log:      $($installLog.log_file)" -ForegroundColor DarkCyan }
Write-Host ""
if ($Update) {
    Write-Host "Naechste Schritte:"
    Write-Host "  cd $script:Bot2BotRoot\scripts; .\verify_install.ps1"
    Write-Host "  cd $TargetDir && webagent.bat brains-health"
} else {
    Write-Host "Naechste Schritte:"
    Write-Host "  cd $script:Bot2BotRoot\scripts"
    Write-Host "  .\oobe_wizard.ps1          # Brains waehlen + Browser-Login"
    Write-Host "  .\verify_install.ps1 -Strict   # nach Login"
    Write-Host "  cd $TargetDir && webagent.bat brains-health"
}
} catch {
    if ($installLog) {
        Report-InstallFailure -Session $installLog -ErrorRecord $_
    } else {
        Write-Host "INSTALL FAILED: $_" -ForegroundColor Red
    }
    exit 1
}