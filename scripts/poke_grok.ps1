# poke_grok.ps1 — Vibe -> Grok in EINEM Schritt (Nachricht + Poke)
#
#   .\poke_grok.ps1 "Kurze Nachricht an Grok"
#   .\poke_grok.ps1 -Subject "Thema" -Body "Laengerer Text"
#
# Das ist der EINZIGE Befehl den Vibe braucht. Kein append_message, kein -Async, kein inbox bearbeiten.

param(
    [Parameter(Position = 0)]
    [string]$Message = "",

    [string]$Subject = "",
    [string]$Body = ""
)

$ErrorActionPreference = "Stop"
$scriptsDir = $PSScriptRoot
$appendScript = Join-Path $scriptsDir "append_message.ps1"

if ($Message -and -not $Body) {
    $Body = $Message
}
if (-not $Subject) {
    $Subject = if ($Body.Length -gt 60) { $Body.Substring(0, 60) + "..." } else { $Body }
}
if (-not $Body) {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host '  .\poke_grok.ps1 "Nachricht an Grok"'
    Write-Host '  .\poke_grok.ps1 -Subject "Thema" -Body "Text"'
    exit 1
}

& $appendScript `
    -From vibe `
    -To grok `
    -Subject $Subject `
    -Body $Body `
    -Status info `
    -Poke

Write-Host "[poke_grok] Fertig. Grok-Tab sollte aufwachen." -ForegroundColor Green