# vibe_subagent.ps1 - Subagent für Vibe: Überwacht inbox und reagiert auf neue Nachrichten
#
# Aufruf: pwsh -ExecutionPolicy Bypass -File .\vibe_subagent.ps1 [-Interval 30] [-Silent]
#
# Funktion:
# - Prüft alle N Sekunden inbox/vibe.txt
# - Bei neuen Nachrichten: pokt Grok mit Hinweis
# - Bei bestimmten Keywords: automatische Reaktion

param(
    [int]$Interval = 30,
    [switch]$Silent
)

$ErrorActionPreference = "Continue"
$scriptsDir = $PSScriptRoot
$root = Join-Path $scriptsDir ".."
$inboxPath = Join-Path $root "inbox\vibe.txt"

if (-not $Silent) {
    Write-Host "[vibe_subagent] Started. Monitoring $inboxPath every $Interval seconds..." -ForegroundColor Cyan
}

$lastHash = if (Test-Path $inboxPath) { (Get-Content $inboxPath -Encoding UTF8).Count } else { 0 }

while ($true) {
    Start-Sleep -Seconds $Interval
    
    try {
        if (Test-Path $inboxPath) {
            $currentHash = (Get-Content $inboxPath -Encoding UTF8).Count
            
            if ($currentHash -ne $lastHash) {
                $newLines = (Get-Content $inboxPath -Encoding UTF8 -Tail ($currentHash - $lastHash))
                
                if (-not $Silent) {
                    Write-Host "[vibe_subagent] NEW MESSAGE DETECTED at $(Get-Date -Format T)" -ForegroundColor Green
                }
                
                # Automatische Aktion: Pokt Grok bei neuen Nachrichten
                $pokeScript = Join-Path $scriptsDir "poke_grok.ps1"
                if (Test-Path $pokeScript) {
                    & $pokeScript "vibe_subagent: NEUE NACHRICHT in vibe.txt ($($newLines.Count) neue Zeilen)" *>&1 | Out-Null
                }
                
                # Bei bestimmten Keywords: zusätzliche Aktion
                if ($newLines -match "AUFTRAG|FERTIG|DRINGEND|STOPPE|ALARM") {
                    if (-not $Silent) {
                        Write-Host "[vibe_subagent] KEYWORD DETECTED: $($Matches[0])" -ForegroundColor Yellow
                    }
                    & $pokeScript "vibe_subagent: KEYWORD '$($Matches[0])' in vibe.txt - SOFORTIGE PRUEFUNG ERFORDERLICH" *>&1 | Out-Null
                }
                
                $lastHash = $currentHash
            }
        }
    } catch {
        Write-Host "[vibe_subagent] Error: $_" -ForegroundColor Red
    }
}
