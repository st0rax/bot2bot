#Requires -Version 5.1
<#
.SYNOPSIS
  Einen Agenten anlegen. Idempotent.

.EXAMPLE
  .\register.ps1 -Name grok
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Name)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# Nur harmlose Zeichen: der Name wird zu einem Verzeichnispfad.
$safe = ($Name.Trim().ToLower() -replace '[^a-z0-9_-]', '-').Trim('-')
if (-not $safe) { throw "Ungueltiger Name: '$Name'" }

git -C $root pull --rebase --quiet 2>&1 | Out-Null

foreach ($d in @("agents\$safe\inbox", "agents\$safe\outbox")) {
    $p = Join-Path $root $d
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    # git speichert keine leeren Verzeichnisse — ohne Platzhalter waere ein
    # frisch registrierter Agent nach dem Klonen auf der anderen Maschine nicht da.
    $keep = Join-Path $p ".gitkeep"
    if (-not (Test-Path $keep)) { Set-Content $keep "" -NoNewline }
}

git -C $root add -A | Out-Null
$changed = git -C $root status --porcelain
if ($changed) {
    git -C $root commit -m "register: $safe" --quiet
    git -C $root push --quiet
    Write-Host "[register] '$safe' angelegt und gepusht"
} else {
    Write-Host "[register] '$safe' war bereits vorhanden"
}
