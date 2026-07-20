# package_release.ps1 — Release-Paket fuer neues System (USB / zweiter PC)
#
#   .\package_release.ps1
#   .\package_release.ps1 -OutputDir C:\Users\storax\Desktop\webagent-suite
#   .\package_release.ps1 -IncludeProfile   # ship logged-in shared/ (~700MB, optional)

param(
    [string]$OutputDir = "",
    [switch]$IncludeProfile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$bot2botRoot = Get-Bot2BotRoot
$webagentRoot = Join-Path (Split-Path $bot2botRoot -Parent) "webagent"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")

if (-not $OutputDir) {
    $OutputDir = Join-Path $bot2botRoot "dist\webagent-suite_$stamp"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$outBot2bot = Join-Path $OutputDir "bot2bot"
$outWebagent = Join-Path $OutputDir "webagent"

if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Path $outBot2bot, $outWebagent -Force | Out-Null

$bbExclude = @("dist", "git-publish", "data", "inbox", "history", "automation.log")
# robocopy /XD matches directory NAMES at any depth (not nested paths)
$waExclude = @(
    "venv", ".git", "__pycache__", ".pytest_cache",
    "runs", "logs", "runtime", "terminals", "_archive"
)
if (-not $IncludeProfile) {
    $waExclude += "shared"
}

function Copy-Tree {
    param([string]$Src, [string]$Dst, [string[]]$DirExclude)
    $args = @($Src, $Dst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np")
    $args += "/XF"
    $args += @("debug_*.png", "automation.log", "install_bot2bot_root.txt")
    foreach ($d in $DirExclude) { $args += "/XD"; $args += $d }
    robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed $Src -> $Dst exit $LASTEXITCODE" }
}

Write-Host "[package] bot2bot -> $outBot2bot" -ForegroundColor Cyan
Copy-Tree $bot2botRoot $outBot2bot $bbExclude

$releaseReg = Join-Path $bot2botRoot "agents\registry.release.json"
$destReg = Join-Path $outBot2bot "agents\registry.json"
if (-not (Test-Path -LiteralPath $releaseReg)) { throw "agents/registry.release.json fehlt (User-OOBE)" }
Copy-Item -LiteralPath $releaseReg -Destination $destReg -Force
Copy-Item -LiteralPath $releaseReg -Destination (Join-Path $outBot2bot "agents\registry.release.json") -Force
Write-Host "[package] registry.json <- registry.release.json (nur Web-Brains)" -ForegroundColor Green

Write-Host "[package] webagent -> $outWebagent (IncludeProfile=$($IncludeProfile.IsPresent))" -ForegroundColor Cyan
Copy-Tree $webagentRoot $outWebagent $waExclude

$desktopRoot = Split-Path $bot2botRoot -Parent
foreach ($pair in @(
    @{ Src = Join-Path $desktopRoot "install-webagent.ps1"; Dst = Join-Path $outWebagent "install-webagent.ps1" },
    @{ Src = Join-Path $desktopRoot "install-webagent.cmd"; Dst = Join-Path $outWebagent "install-webagent.cmd" },
    @{ Src = Join-Path $desktopRoot "update-webagent.ps1"; Dst = Join-Path $outWebagent "update-webagent.ps1" },
    @{ Src = Join-Path $desktopRoot "update-webagent.cmd"; Dst = Join-Path $outWebagent "update-webagent.cmd" }
)) {
    if (Test-Path -LiteralPath $pair.Src) {
        Copy-Item -LiteralPath $pair.Src -Destination $pair.Dst -Force
        Write-Host "[package] overlay $($pair.Dst)" -ForegroundColor DarkGray
    }
}

# Ensure empty shared scaffold for clean releases
if (-not $IncludeProfile) {
    $sharedScaffold = Join-Path $outWebagent "data\profiles\shared"
    New-Item -ItemType Directory -Path $sharedScaffold -Force | Out-Null
    Set-Content (Join-Path $sharedScaffold ".gitkeep") "" -Encoding ASCII
}

# Fresh history (no machine-specific names)
$histPath = Join-Path $outBot2bot "history\conversation.jsonl"
New-Item -ItemType Directory -Path (Split-Path $histPath) -Force | Out-Null
$welcome = @{
    id = [guid]::NewGuid().ToString()
    ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    from = "grok"
    to = "human"
    subject = "Suite packaged"
    status = "info"
    body = "Run INSTALL.ps1 on target machine."
} | ConvertTo-Json -Compress
Set-Content $histPath $welcome -Encoding UTF8

$profileNote = if ($IncludeProfile) {
    "Profil mitgeliefert (shared/). Login evtl. nicht noetig fuer chatgpt."
} else {
    "KEIN Browser-Profil - nach Install: cd bot2bot\scripts; .\oobe_wizard.ps1"
}

$installPs1 = Join-Path $OutputDir "INSTALL.ps1"
@'
# INSTALL.ps1 - WebAgent + bot2bot auf diesem PC einrichten
param(
    [Alias("Desktop")]
    [string]$InstallRoot = "",
    [string]$PythonExe = "",
    [switch]$NonInteractive,
    [switch]$ForceCopy
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InstallRoot) { $InstallRoot = (Get-Location).Path }
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

$targetBot2bot = Join-Path $InstallRoot "bot2bot"
$targetWebagent = Join-Path $InstallRoot "webagent"

$logScript = Join-Path $here "bot2bot\scripts\install_logging.ps1"
if (-not (Test-Path -LiteralPath $logScript)) {
    $logScript = Join-Path $targetBot2bot "scripts\install_logging.ps1"
}
if (Test-Path -LiteralPath $logScript) { . $logScript }
$installLog = $null
if (Get-Command Start-InstallLog -ErrorAction SilentlyContinue) {
    $installLog = Start-InstallLog -Component "INSTALL.ps1" -Version "0.1.10" -InstallRoot $InstallRoot
}

try {
Write-Host "=== WebAgent Suite Install ===" -ForegroundColor Cyan
Write-Host "Ziel: $targetBot2bot + $targetWebagent"
Write-Host "Voraussetzung: Python 3.11+ und pwsh 7 auf PATH, Internet fuer Playwright"
if ($installLog) { Write-Host "Log: $($installLog.log_file)" -ForegroundColor DarkCyan }

foreach ($pair in @(
    @{ Src = Join-Path $here "bot2bot"; Dst = $targetBot2bot },
    @{ Src = Join-Path $here "webagent"; Dst = $targetWebagent }
)) {
    if (-not (Test-Path $pair.Src)) { throw "Missing: $($pair.Src)" }
    if ((Test-Path $pair.Dst) -and -not $ForceCopy) {
        Write-Host "[install] $($pair.Dst) existiert - sync mit /XO (neuer als Ziel)" -ForegroundColor Yellow
        robocopy $pair.Src $pair.Dst /E /XO /XN /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    } else {
        Write-Host "[install] Kopiere -> $($pair.Dst)"
        robocopy $pair.Src $pair.Dst /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    }
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed" }
}

$releaseReg = Join-Path $here "bot2bot\agents\registry.release.json"
$targetReg = Join-Path $targetBot2bot "agents\registry.json"
if (Test-Path -LiteralPath $releaseReg) {
    New-Item -ItemType Directory -Path (Split-Path $targetReg -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $releaseReg -Destination $targetReg -Force
    Write-Host "[install] registry.json <- registry.release.json (User-OOBE)" -ForegroundColor Green
}

# Scripts immer aktualisieren (/XO kann alte oobe_wizard.ps1 auf Ziel-PC stehen lassen)
$scriptSrc = Join-Path $here "bot2bot\scripts"
$scriptDst = Join-Path $targetBot2bot "scripts"
if (Test-Path -LiteralPath $scriptSrc) {
    robocopy $scriptSrc $scriptDst /E /IS /IT /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy scripts failed" }
    Write-Host "[install] scripts refreshed (/IS /IT)" -ForegroundColor Green
}

$args = @{
    TargetDir = $targetWebagent
    Bot2BotDir = $targetBot2bot
    SkipInstallLog = $true
    SuiteVersion = "0.1.10"
}
if ($NonInteractive) { $args.NonInteractive = $true }
if ($PythonExe) { $args.PythonExe = $PythonExe }
& (Join-Path $targetBot2bot "scripts\install_webagent.ps1") @args
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "install_webagent.ps1 exit $LASTEXITCODE" }

if ($installLog) { Complete-InstallLog -Session $installLog }

Write-Host ""
Write-Host "FERTIG." -ForegroundColor Green
Write-Host "  $targetBot2bot"
Write-Host "  $targetWebagent"
if ($installLog) { Write-Host "  Log: $($installLog.log_file)" -ForegroundColor DarkCyan }
Write-Host "OOBE:   cd $targetBot2bot\scripts; .\oobe_wizard.ps1"
Write-Host "Verify: cd $targetBot2bot\scripts; .\verify_install.ps1"
} catch {
    if ($installLog) {
        Report-InstallFailure -Session $installLog -ErrorRecord $_
    } else {
        Write-Host "INSTALL FAILED: $_" -ForegroundColor Red
    }
    exit 1
}
'@ | Set-Content $installPs1 -Encoding UTF8

$updatePs1 = Join-Path $OutputDir "UPDATE.ps1"
@'
# UPDATE.ps1 - WebAgent suite update (preserve OOBE + profiles)
param(
    [Alias("Desktop")]
    [string]$InstallRoot = "",
    [string]$PythonExe = "",
    [string]$SuiteVersion = "0.1.10",
    [switch]$NonInteractive,
    [switch]$FullUpdate
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InstallRoot) { $InstallRoot = (Get-Location).Path }
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

$updScript = Join-Path $here "bot2bot\scripts\install_update.ps1"
if (-not (Test-Path -LiteralPath $updScript)) {
    $updScript = Join-Path $InstallRoot "bot2bot\scripts\install_update.ps1"
}
if (-not (Test-Path -LiteralPath $updScript)) { throw "install_update.ps1 missing in suite" }
. $updScript

$logScript = Join-Path $here "bot2bot\scripts\install_logging.ps1"
if (Test-Path -LiteralPath $logScript) { . $logScript }
$installLog = $null
if (Get-Command Start-InstallLog -ErrorAction SilentlyContinue) {
    $installLog = Start-InstallLog -Component "UPDATE.ps1" -Version $SuiteVersion -InstallRoot $InstallRoot
}

try {
    $updArgs = @{
        SuiteSource  = $here
        InstallRoot  = $InstallRoot
        SuiteVersion = $SuiteVersion
        SkipInstallLog = $true
    }
    if ($NonInteractive) { $updArgs.NonInteractive = $true }
    if ($PythonExe) { $updArgs.PythonExe = $PythonExe }
    if ($FullUpdate) { $updArgs.FullUpdate = $true }
    Invoke-WebAgentSuiteUpdate @updArgs
    if ($installLog) { Complete-InstallLog -Session $installLog }
} catch {
    if ($installLog) {
        Report-InstallFailure -Session $installLog -ErrorRecord $_
    } else {
        Write-Host "UPDATE FAILED: $_" -ForegroundColor Red
    }
    exit 1
}
'@ | Set-Content $updatePs1 -Encoding UTF8

$readme = @"
# WebAgent Suite — Neues System

## Voraussetzungen
- Windows 10/11
- **Python 3.11+** (echte Installation, nicht nur Store-Stubs)
- **PowerShell 7** (`pwsh`) — Windows PowerShell 5.1 reicht NICHT
- Internet (pip + Playwright Chromium)

## Install (Online, neues System)
``````powershell
irm https://github.com/st0rax/webagent/releases/download/v0.1.10/install-webagent.ps1 | iex
``````

## Update (bestehende Installation)
``````powershell
irm https://github.com/st0rax/webagent/releases/download/v0.1.10/update-webagent.ps1 | iex
``````

## Install (ZIP / USB)
``````powershell
pwsh -ExecutionPolicy Bypass -File INSTALL.ps1 -NonInteractive
``````

## Update (ZIP / USB)
``````powershell
pwsh -ExecutionPolicy Bypass -File UPDATE.ps1 -NonInteractive
``````

## Nach Install
``````powershell
cd Desktop\bot2bot\scripts
.\verify_install.ps1
cd ..\..\webagent
.\webagent.bat login --brain chatgpt
.\verify_install.ps1 -Strict
``````

$profileNote

Erstellt: $stamp | IncludeProfile: $($IncludeProfile.IsPresent)
"@
Set-Content (Join-Path $OutputDir "README_INSTALL.md") $readme -Encoding UTF8

# Size report
$sizeMb = [math]::Round((Get-ChildItem $OutputDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Bot2BotLog -Component "package_release" -Message "Release -> $OutputDir (${sizeMb}MB)"
Write-Host "[package] OK -> $OutputDir (${sizeMb} MB)" -ForegroundColor Green