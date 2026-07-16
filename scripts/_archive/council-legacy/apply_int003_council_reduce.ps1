# apply_int003_council_reduce.ps1 — Council-Mehrheit reduce: claude -10 -> -5
param(
    [int]$ReducedClaudeMalus = -5,
    [string]$IndexPath = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$indexPath = if ($IndexPath) { $IndexPath } else { Join-Path $root "data\leistungsindex.json" }
$idx = Get-Content $indexPath -Raw | ConvertFrom-Json

$current = [int]$idx.participants.claude.score
if ($current -ne -10) {
    Write-Host "[INT-003-reduce] claude score=$current (expected -10) — skip or manual review" -ForegroundColor Yellow
}
$adjustment = $ReducedClaudeMalus - $current
if ($adjustment -eq 0) {
    Write-Host "[INT-003-reduce] already at $ReducedClaudeMalus"
    exit 0
}

$idx.participants.claude.score = $ReducedClaudeMalus
$idx.participants.claude | Add-Member -NotePropertyName council_adjusted -NotePropertyValue $true -Force
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$idx.events += [pscustomobject][ordered]@{
    id      = "INT-003-council-reduce"
    ts      = $ts
    kind    = "council_adjustment"
    agent   = "claude"
    delta   = @{ claude = $adjustment }
    reason  = "Combined Council Mehrheit INT003=reduce; Ziel $ReducedClaudeMalus (war -10)"
    context = "INT-003"
    refs    = @("combined_council_b6c4515f186b", "98db941d")
}

$idx.policy.revised_at = $ts
$idx.policy.revised_by = "grok"
$idx.policy.rules += "INT-003: Original -10 per grok+vibe; Council reduce auf -5 angewendet (Release v0.1.1)."

$idx | ConvertTo-Json -Depth 14 | Set-Content -Path $indexPath -Encoding UTF8
Write-Host "[INT-003-reduce] claude $current -> $ReducedClaudeMalus (delta $adjustment)" -ForegroundColor Green