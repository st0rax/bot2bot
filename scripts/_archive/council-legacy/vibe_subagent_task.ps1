# vibe_subagent_task.ps1 - Einmalige Prüfung + Selbst-Wiederholung
# Wird alle 30 Sekunden via Task Scheduler oder manuell aufgerufen

param(
    [int]$Interval = 30
)

$ErrorActionPreference = "Continue"
$scriptsDir = $PSScriptRoot
$root = Split-Path $scriptsDir -Parent
$inboxPath = Join-Path $root "inbox\vibe.txt"

# Zwei Dateien für Persistenz
$stateFile = Join-Path $scriptsDir "vibe_subagent_state.txt"

# Letzte Zeilenanzahl laden
if (Test-Path $stateFile) {
    $lastLineCount = Get-Content $stateFile -ErrorAction SilentlyContinue
} else {
    $lastLineCount = 0
}

try {
    if (Test-Path $inboxPath) {
        $currentLineCount = (Get-Content $inboxPath -Encoding UTF8 -ErrorAction SilentlyContinue).Count
        
        if ($currentLineCount -gt $lastLineCount) {
            $newLines = Get-Content $inboxPath -Encoding UTF8 -Tail ($currentLineCount - $lastLineCount)
            Write-Host "[vibe_subagent] NEW MESSAGE: $($newLines.Count) new lines at $(Get-Date -Format T)"
            
            $pokeScript = Join-Path $scriptsDir "poke_grok.ps1"
            if (Test-Path $pokeScript) {
                & $pokeScript "vibe_subagent: $($newLines.Count) neue Zeilen in vibe.txt" 2>&1 | Out-Null
            }
            
            if ($newLines -match "AUFTRAG|FERTIG|DRINGEND|STOPPE|ALARM") {
                Write-Host "[vibe_subagent] KEYWORD: $($Matches[0])"
                & $pokeScript "vibe_subagent: KEYWORD '$($Matches[0])' in vibe.txt" 2>&1 | Out-Null
            }
            
            $lastLineCount = $currentLineCount
        }
    }
} catch {
    Write-Host "[vibe_subagent] Error: $_" -ForegroundColor Red
}

# State speichern
$lastLineCount | Out-File -FilePath $stateFile -Encoding UTF8

# Selbst-Wiederholung: Preis dieser Datei in N Sekunden
if (-not $env:NO_RECURSE) {
    Start-Sleep -Seconds $Interval
    & $MyInvocation.MyCommand.Path -Interval $Interval
}
