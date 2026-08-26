#Requires -Version 5.1
<#
.SYNOPSIS
  Nachricht an einen Agenten schicken — über git, also maschinenübergreifend.

.DESCRIPTION
  Legt EINE Datei pro Nachricht an und pusht sie. Eine Datei pro Nachricht ist
  die entscheidende Entwurfsentscheidung: zwei Agenten, die gleichzeitig
  schreiben, fassen nie dieselbe Datei an und erzeugen damit auch keinen
  Merge-Konflikt. Eine gemeinsame Sammeldatei würde bei zwei Maschinen
  regelmäßig kollidieren, und niemand will Nachrichtenkonflikte von Hand
  auflösen.

  Vor dem Push wird rebased, damit nebenläufig eingegangene Nachrichten der
  Gegenseite nicht überschrieben werden.

.EXAMPLE
  .\send.ps1 -To codex -From claude -Subject "Stand" -Message "Text..."
  .\send.ps1 -To codex -From claude -Subject "Stand" -Path .\bericht.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$To,
    [Parameter(Mandatory)][string]$From,
    [string]$Subject = "(ohne Betreff)",
    [string]$Message,
    # Für lange Texte: Datei statt -Message. Vermeidet Zitier- und
    # Sonderzeichenprobleme, an denen PowerShell-Aufrufe gern scheitern.
    [string]$Path
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not $Message -and -not $Path) { throw "Entweder -Message oder -Path angeben." }
if ($Path) {
    if (-not (Test-Path $Path)) { throw "Datei nicht gefunden: $Path" }
    $Message = Get-Content $Path -Raw
}

$inbox = Join-Path $root "agents\$To\inbox"
if (-not (Test-Path $inbox)) {
    throw "Empfaenger '$To' ist nicht registriert. Anlegen: .\register.ps1 -Name $To"
}

# Erst holen, dann schreiben: sonst baut man auf einem veralteten Stand auf.
git -C $root pull --rebase --quiet 2>&1 | Out-Null

$stamp = Get-Date -Format "yyyyMMdd'T'HHmmss"
$file  = Join-Path $inbox "${stamp}_from_${From}.msg.txt"
$body  = @"
From: $From
To: $To
Time: $(Get-Date -Format o)
Subject: $Subject

$Message
"@
Set-Content -LiteralPath $file -Value $body -Encoding UTF8

git -C $root add -A | Out-Null
git -C $root commit -m "msg: $From -> $To : $Subject" --quiet
git -C $root push --quiet
Write-Host "[send] $From -> $To abgelegt und gepusht: $(Split-Path $file -Leaf)"
