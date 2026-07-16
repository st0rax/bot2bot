# PS 5.1 checks for OOBE (parser + active-property mutation)
$ErrorActionPreference = "Stop"

foreach ($name in @("oobe_wizard.ps1", "first_login_wizard.ps1")) {
    $path = Join-Path $PSScriptRoot $name
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) {
        $parseErrors | ForEach-Object { Write-Host "[FAIL] $name $_" -ForegroundColor Red }
        exit 1
    }
    $text = [System.IO.File]::ReadAllText($path)
    if ($text -match '[^\x00-\x7F]') {
        Write-Host "[FAIL] $name enthaelt Nicht-ASCII" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] $name PS5.1 parser + ASCII" -ForegroundColor Green
}

$json = '{"chatgpt":{"kind":"webbrain","brain_id":"chatgpt","display_name":"ChatGPT"}}'
$entry = ($json | ConvertFrom-Json).chatgpt
try {
    $entry.active = $false
    Write-Host "[FAIL] direct active= should throw on PS5.1" -ForegroundColor Red
    exit 1
} catch {
    Write-Host "[OK] direct active= fails as expected on PS5.1" -ForegroundColor Green
}
$entry | Add-Member -NotePropertyName active -NotePropertyValue $false -Force
if (-not ($entry.active -eq $false)) {
    Write-Host "[FAIL] Add-Member active set failed" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Add-Member active workaround" -ForegroundColor Green
exit 0