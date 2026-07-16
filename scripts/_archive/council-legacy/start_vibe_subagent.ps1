# start_vibe_subagent.ps1 - Startet den Vibe Subagent als Hintergrundprozess
param(
    [int]$Interval = 30
)

$script = Join-Path $PSScriptRoot "vibe_subagent.ps1"
if (-not (Test-Path $script)) {
    Write-Host "vibe_subagent.ps1 nicht gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "[start_vibe_subagent] Starte vibe_subagent.ps1 als Hintergrundprozess..." -ForegroundColor Cyan
Write-Host "  Intervall: $Interval Sekunden" -ForegroundColor Cyan

$process = Start-Process -FilePath "pwsh" -ArgumentList "-ExecutionPolicy Bypass -File `$script -Interval $Interval" -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden

if ($process) {
    Write-Host "[start_vibe_subagent] Subagent gestartet: PID=$($process.Id)" -ForegroundColor Green
    Write-Host "  Ueberpruefe mit: Get-Process -Id $($process.Id)" -ForegroundColor DarkGray
} else {
    Write-Host "[start_vibe_subagent] FEHLER: Subagent konnte nicht gestartet werden" -ForegroundColor Red
    exit 1
}
