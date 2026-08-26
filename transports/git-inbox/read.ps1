#Requires -Version 5.1
<#
.SYNOPSIS
  Eigene Nachrichten holen und anzeigen.

.DESCRIPTION
  Holt zuerst den aktuellen Stand (`git pull --rebase`) — ohne das liest man
  auf einer zweiten Maschine seine eigene Vergangenheit.

  Mit -Ack werden gelesene Nachrichten nach `outbox/` VERSCHOBEN, nicht
  gelöscht. Löschen wäre auf zwei Maschinen gefährlich: der eine entfernt eine
  Datei, während der andere sie gerade zieht, und die Nachricht ist weg, ohne
  dass jemand sie gesehen hat. Verschieben bleibt nachvollziehbar und ist im
  git-Verlauf umkehrbar.

.EXAMPLE
  .\read.ps1 -Agent claude
  .\read.ps1 -Agent claude -Ack
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Agent,
    # Gelesene Nachrichten nach outbox/ verschieben und den Stand pushen.
    [switch]$Ack,
    [int]$Last = 0
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

git -C $root pull --rebase --quiet 2>&1 | Out-Null

$inbox = Join-Path $root "agents\$Agent\inbox"
if (-not (Test-Path $inbox)) {
    throw "Agent '$Agent' ist nicht registriert. Anlegen: .\register.ps1 -Name $Agent"
}

$msgs = Get-ChildItem $inbox -File -Filter "*.msg.txt" | Sort-Object Name
if ($Last -gt 0 -and $msgs.Count -gt $Last) { $msgs = $msgs | Select-Object -Last $Last }

if (-not $msgs) {
    Write-Host "[read] $Agent : keine ungelesenen Nachrichten"
    return
}

foreach ($m in $msgs) {
    Write-Host "===== $($m.Name) ====="
    Get-Content $m.FullName
    Write-Host ""
}
Write-Host "[read] $Agent : $($msgs.Count) Nachricht(en)"

if ($Ack) {
    $outbox = Join-Path $root "agents\$Agent\outbox"
    New-Item -ItemType Directory -Path $outbox -Force | Out-Null
    foreach ($m in $msgs) { Move-Item -LiteralPath $m.FullName -Destination $outbox -Force }
    git -C $root add -A | Out-Null
    git -C $root commit -m "ack: $Agent hat $($msgs.Count) Nachricht(en) gelesen" --quiet
    git -C $root push --quiet
    Write-Host "[read] nach outbox/ verschoben und gepusht"
}
