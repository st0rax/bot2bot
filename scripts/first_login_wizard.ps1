# first_login_wizard.ps1 - Browser-Login fuer alle Brains (neues System)
#
#   .\first_login_wizard.ps1
#   .\first_login_wizard.ps1 -WebagentRoot C:\path\webagent -Brains chatgpt,kimi

param(
    [string]$WebagentRoot = "",
    [string]$Brains = "chatgpt,deepseek,kimi,gemini,qwen,mistral,claude,zai",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
if (-not $WebagentRoot) {
    $WebagentRoot = Join-Path (Split-Path $root -Parent) "webagent"
    $link = Join-Path $WebagentRoot "data\install_bot2bot_root.txt"
    if (Test-Path $link) { $root = (Get-Content $link -Raw).Trim() }
}

$bat = Join-Path $WebagentRoot "webagent.bat"
if (-not (Test-Path $bat)) { throw "webagent.bat not found: $bat" }

$list = $Brains.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
Write-Host "=== First Login Wizard ===" -ForegroundColor Cyan
Write-Host "webagent: $WebagentRoot"
Write-Host "brains:   $($list -join ', ')"
Write-Host ""
Write-Host "Jeder Brain oeffnet einen Browser - bitte einloggen und Dialoge schliessen."
Write-Host "Abbrechen: Ctrl+C"
Write-Host ""

foreach ($brain in $list) {
    Write-Host "--- login: $brain ---" -ForegroundColor Yellow
    if ($DryRun) {
        Write-Host "  DRY: $bat login --brain $brain"
        continue
    }
    Push-Location $WebagentRoot
    try {
        & $bat login --brain $brain
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "login $brain exit $LASTEXITCODE - weiter mit naechstem Brain"
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "Verify:" -ForegroundColor Green
Write-Host "  cd $root\scripts"
Write-Host "  .\verify_install.ps1 -Strict"