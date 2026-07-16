# install_update.ps1 - WebAgent suite update (preserve OOBE, profiles, history)
#
#   . .\install_update.ps1
#   Invoke-WebAgentSuiteUpdate -SuiteSource C:\suite -InstallRoot C:\Ziel -SuiteVersion 0.1.10

function Get-InstallManifestPath {
    param([string]$Bot2BotRoot)
    return Join-Path $Bot2BotRoot "data\install_manifest.json"
}

function Get-ExistingInstallManifest {
    param([string]$Bot2BotRoot)
    $path = Get-InstallManifestPath -Bot2BotRoot $Bot2BotRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-WebAgentInstallExists {
    param([string]$InstallRoot)
    $installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
    $bb = Join-Path $installRoot "bot2bot"
    $wa = Join-Path $installRoot "webagent"
    $manifest = Get-InstallManifestPath -Bot2BotRoot $bb
    $venv = Join-Path $wa "venv\Scripts\python.exe"
    $registry = Join-Path $bb "agents\registry.json"
    return (Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $venv) -and (Test-Path -LiteralPath $registry)
}

function Invoke-RobocopySafe {
    param([string[]]$Args)
    robocopy @Args | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed exit $LASTEXITCODE" }
}

function Sync-Bot2BotForUpdate {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot
    )
    if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "bot2bot source missing: $SourceRoot" }
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

    $exclude = @("history", "inbox", "data", "dist", "git-publish")
    $rc = @(
        $SourceRoot, $TargetRoot, "/E",
        "/XD") + $exclude + @(
        "/XF", "registry.json", "automation.log",
        "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np"
    )
    Write-Host "[update] bot2bot sync (preserve history/inbox/data/registry)" -ForegroundColor Cyan
    Invoke-RobocopySafe -Args $rc

    $scriptSrc = Join-Path $SourceRoot "scripts"
    $scriptDst = Join-Path $TargetRoot "scripts"
    if (Test-Path -LiteralPath $scriptSrc) {
        New-Item -ItemType Directory -Path $scriptDst -Force | Out-Null
        Invoke-RobocopySafe -Args @(
            $scriptSrc, $scriptDst, "/E", "/IS", "/IT",
            "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np"
        )
        Write-Host "[update] bot2bot scripts refreshed (/IS /IT)" -ForegroundColor Green
    }
}

function Sync-WebagentForUpdate {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot
    )
    if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "webagent source missing: $SourceRoot" }
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

    $exclude = @(
        "venv", ".git", "__pycache__", "runs", ".pytest_cache",
        "runtime", "terminals", "_archive", "logs", "shared"
    )
    $rc = @(
        $SourceRoot, $TargetRoot, "/E",
        "/XD") + $exclude + @(
        "/XF", "debug_*.png", "automation.log", "install_bot2bot_root.txt",
        "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np"
    )
    Write-Host "[update] webagent sync (preserve venv + shared profile)" -ForegroundColor Cyan
    Invoke-RobocopySafe -Args $rc
}

function Update-InstallManifest {
    param(
        [string]$Bot2BotRoot,
        [string]$WebagentRoot,
        [string]$SuiteVersion,
        [string]$PythonVersion,
        [bool]$Playwright,
        [string]$VerifyStatus = "passed"
    )
    $path = Get-InstallManifestPath -Bot2BotRoot $Bot2BotRoot
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null

    $existing = Get-ExistingInstallManifest -Bot2BotRoot $Bot2BotRoot
    $installedAt = if ($existing -and $existing.installed_at) {
        [string]$existing.installed_at
    } else {
        (Get-Date).ToUniversalTime().ToString("o")
    }

    $manifest = @{
        installed_at  = $installedAt
        updated_at    = (Get-Date).ToUniversalTime().ToString("o")
        suite_version = $SuiteVersion
        python        = $PythonVersion.Trim()
        bot2bot_root  = $Bot2BotRoot
        webagent_root = $WebagentRoot
        shared_browser = $true
        playwright    = $Playwright
        verify        = $VerifyStatus
        mode          = "update"
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-WebAgentSuiteUpdate {
    param(
        [Parameter(Mandatory)][string]$SuiteSource,
        [Parameter(Mandatory)][string]$InstallRoot,
        [string]$SuiteVersion = "0.1.10",
        [string]$PythonExe = "",
        [switch]$NonInteractive,
        [switch]$SkipPlaywright,
        [switch]$FullUpdate,
        [switch]$SkipInstallLog
    )

    $ErrorActionPreference = "Stop"
    $InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
    if (-not (Test-WebAgentInstallExists -InstallRoot $InstallRoot)) {
        throw "Keine bestehende Installation in $InstallRoot (bot2bot+webagent+venv). Erst installieren: install-webagent.ps1"
    }

    $srcBot2bot = Join-Path $SuiteSource "bot2bot"
    $srcWebagent = Join-Path $SuiteSource "webagent"
    $tgtBot2bot = Join-Path $InstallRoot "bot2bot"
    $tgtWebagent = Join-Path $InstallRoot "webagent"

    $prev = Get-ExistingInstallManifest -Bot2BotRoot $tgtBot2bot
    $prevVer = if ($prev -and $prev.suite_version) { [string]$prev.suite_version } else { "(unknown)" }
    Write-Host ""
    Write-Host "=== WebAgent Suite Update v$SuiteVersion ===" -ForegroundColor Cyan
    Write-Host "Install root: $InstallRoot"
    Write-Host "Previous:     $prevVer"
    Write-Host "Target:       $SuiteVersion"
    Write-Host ""

    Sync-Bot2BotForUpdate -SourceRoot $srcBot2bot -TargetRoot $tgtBot2bot
    Sync-WebagentForUpdate -SourceRoot $srcWebagent -TargetRoot $tgtWebagent

    $skipPw = $SkipPlaywright
    if (-not $PSBoundParameters.ContainsKey('SkipPlaywright') -and -not $FullUpdate) {
        $skipPw = $true
    }
    if ($env:WA_INSTALL_SKIP_PLAYWRIGHT -eq "1") { $skipPw = $true }

    $iwArgs = @{
        TargetDir      = $tgtWebagent
        Bot2BotDir     = $tgtBot2bot
        SkipInstallLog = $true
        Update         = $true
        SuiteVersion   = $SuiteVersion
    }
    if ($NonInteractive) { $iwArgs.NonInteractive = $true }
    if ($PythonExe) { $iwArgs.PythonExe = $PythonExe }
    if ($skipPw) { $iwArgs.SkipPlaywright = $true }
    if ($FullUpdate) { $iwArgs.FullUpdate = $true }

    $installScript = Join-Path $tgtBot2bot "scripts\install_webagent.ps1"
    if (-not (Test-Path -LiteralPath $installScript)) {
        $installScript = Join-Path $PSScriptRoot "install_webagent.ps1"
    }
    & $installScript @iwArgs
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "install_webagent.ps1 update exit $LASTEXITCODE" }

    Write-Host ""
    Write-Host "UPDATE FERTIG v$SuiteVersion" -ForegroundColor Green
    Write-Host "  $tgtBot2bot"
    Write-Host "  $tgtWebagent"
    Write-Host "Verify: cd $tgtBot2bot\scripts; .\verify_install.ps1"
}