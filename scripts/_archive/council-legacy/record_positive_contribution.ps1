# record_positive_contribution.ps1 — P4 Positiv-Zaehler (verifizierte Beitraege)
param(
    [Parameter(Mandatory)]
    [string]$Agent,

    [Parameter(Mandatory)]
    [ValidateSet("diff_applied", "bug_fixed", "artifact_caught", "release_verified", "other")]
    [string]$Category,

    [Parameter(Mandatory)]
    [string]$Reason,

    [string]$Ref = "",
    [string]$IndexPath = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$indexPath = if ($IndexPath) { $IndexPath } else { Join-Path $root "data\leistungsindex.json" }
$idx = Get-Content $indexPath -Raw | ConvertFrom-Json
$slug = $Agent.ToLower()

if (-not $idx.participants.$slug) {
    throw "Unknown agent: $Agent"
}
$p = $idx.participants.$slug
if (-not (Get-Member -InputObject $p -Name positive_contributions -MemberType NoteProperty, Property -ErrorAction SilentlyContinue)) {
    $p | Add-Member -NotePropertyName positive_contributions -NotePropertyValue 0 -Force
}
if (-not (Get-Member -InputObject $p -Name positive_events -MemberType NoteProperty, Property -ErrorAction SilentlyContinue)) {
    $p | Add-Member -NotePropertyName positive_events -NotePropertyValue @() -Force
}

$p.positive_contributions = [int]$p.positive_contributions + 1
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$ev = [pscustomobject]@{ ts = $ts; category = $Category; reason = $Reason; ref = $Ref }
$p.positive_events = @($p.positive_events) + $ev

$idx.events += [pscustomobject][ordered]@{
    id      = "P4-pos-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    ts      = $ts
    kind    = "positive_contribution"
    agent   = $slug
    delta   = @{ positive = 1 }
    reason  = "[$Category] $Reason"
    context = "P4"
}

$idx | ConvertTo-Json -Depth 14 | Set-Content -Path $indexPath -Encoding UTF8
Write-Host "[P4] $slug positive_contributions=$($p.positive_contributions) ($Category)" -ForegroundColor Green