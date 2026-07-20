# Simulates: irm URL | iex (PSCommandPath empty)
# Run under Windows PowerShell 5.1 to match fresh PCs:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\test_iex_bootstrap.ps1 -LocalScript ..\dist\install-webagent.ps1

param(
    [string]$Version = "0.1.6",
    [string]$LocalScript = "",
    [Alias("Desktop")]
    [string]$InstallRoot = "",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($LocalScript) {
    if (-not (Test-Path -LiteralPath $LocalScript)) { throw "LocalScript not found: $LocalScript" }
    $code = [System.IO.File]::ReadAllText($LocalScript)
    $bootstrapCopy = Join-Path $env:TEMP "install-webagent_iextest.ps1"
    Copy-Item -LiteralPath $LocalScript -Destination $bootstrapCopy -Force
    $env:WA_INSTALL_BOOTSTRAP_FILE = $bootstrapCopy

    $distDir = Split-Path -Parent $LocalScript
    $ensureLocal = Join-Path $distDir "ensure_prerequisites.ps1"
    $ensureVersioned = Join-Path $env:TEMP "ensure_prerequisites_v$Version.ps1"
    if (Test-Path -LiteralPath $ensureLocal) {
        Copy-Item -LiteralPath $ensureLocal -Destination $ensureVersioned -Force
    }
    $zipLocal = Join-Path $distDir "webagent-suite_v$Version.zip"
    if (Test-Path -LiteralPath $zipLocal) {
        $env:WA_INSTALL_LOCAL_ZIP = $zipLocal
    }
    Write-Host "[iex-test] local script: $LocalScript" -ForegroundColor Cyan
} else {
    $url = "https://github.com/st0rax/webagent/releases/download/v$Version/install-webagent.ps1"
    $code = Invoke-RestMethod -Uri $url -TimeoutSec 120
    Write-Host "[iex-test] live script: $url" -ForegroundColor Cyan
}

if ($InstallRoot) { $env:WA_INSTALL_ROOT = $InstallRoot }
if ($NonInteractive) {
    $env:WA_INSTALL_NONINTERACTIVE = "1"
    $env:WA_INSTALL_SKIP_PLAYWRIGHT = "1"
}

try {
    Invoke-Expression $code
    exit $LASTEXITCODE
} catch {
    if ($_.Exception.Message -match 'Path|PSScriptRoot|PSCommandPath') {
        Write-Host "IEX PATH BIND FAIL: $_" -ForegroundColor Red
    }
    throw
}