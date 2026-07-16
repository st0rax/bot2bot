# finalize_prop_sys001.ps1 — Council-Ergebnisse -> Finalplan
param([string]$ReviewJson = "")

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$reviewDir = Join-Path $root "data\deputy_reviews"
$outPath = Join-Path $root "data\proposals\PROP_SYS_001_FINAL.md"

if (-not $ReviewJson) {
    $latest = Get-ChildItem $reviewDir -Filter "prop_sys001_council_*.json" -EA SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) {
        $latest = Get-ChildItem $reviewDir -Filter "deputy_proposal_*.json" -EA SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $latest) { throw "No council review JSON found in $reviewDir" }
    $ReviewJson = $latest.FullName
}

$data = Get-Content $ReviewJson -Raw | ConvertFrom-Json
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$approve = @(); $reject = @(); $escalate = @(); $failed = @()
foreach ($r in $data.results) {
    $row = [PSCustomObject]@{
        Brain = $r.brain
        Verdict = $r.verdict
        Reason = $r.reason
        Ok = $r.ok
        Error = $r.error
    }
    if (-not $r.ok) { $failed += $row; continue }
    switch ($r.verdict) {
        "approve" { $approve += $row }
        "reject" { $reject += $row }
        "escalate" { $escalate += $row }
        default { $failed += $row }
    }
}

$consensus = if ($reject.Count -eq 0 -and $approve.Count -ge 4) { "GO" }
elseif ($reject.Count -gt $approve.Count) { "NO-GO" }
else { "CONDITIONAL" }

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("# PROP_SYS_001 — Finalplan (Council)")
[void]$lines.Add("")
[void]$lines.Add("Synthesized: $stamp")
[void]$lines.Add("Review source: $ReviewJson")
[void]$lines.Add("Consensus: **$consensus** ($($approve.Count) approve, $($reject.Count) reject, $($escalate.Count) escalate, $($failed.Count) failed)")
[void]$lines.Add("")
[void]$lines.Add("## Brain-Votes")
[void]$lines.Add("| Brain | Verdict | Reason |")
[void]$lines.Add("|-------|---------|--------|")
foreach ($r in ($approve + $reject + $escalate + $failed | Sort-Object Brain)) {
    $v = if ($r.Verdict) { $r.Verdict } else { "FAIL" }
    $reason = ($r.Reason -replace '\|','/').Substring(0, [Math]::Min(80, ($r.Reason).Length))
    if (-not $reason -and $r.Error) { $reason = $r.Error.Substring(0, [Math]::Min(80, $r.Error.Length)) }
    [void]$lines.Add("| $($r.Brain) | $v | $reason |")
}
[void]$lines.Add("")
[void]$lines.Add("## Finalplan (3 Phasen)")
[void]$lines.Add("")
[void]$lines.Add("### Phase A — Sofort (LOW risk)")
[void]$lines.Add("- A1: wa_install_test geloescht — DONE")
[void]$lines.Add("- A2: web2terminal README LEGACY-Banner")
[void]$lines.Add("- A3: consensus/PROJECT.md infra-only")
[void]$lines.Add("- A4: system_recon.md + dieser Finalplan")
[void]$lines.Add("")
[void]$lines.Add("### Phase B — Storax-Freigabe (MED/HIGH)")
[void]$lines.Add("- B1: _alt_desktop (30 GB) -> USB/D:\\Archive (Rollback: Kopie behalten bis Storax OK)")
[void]$lines.Add("- B2: resc (1.4 GB) off-Desktop")
[void]$lines.Add("- B3: FRIGO IT_DOK Credentials -> Vault, Klartext entfernen")
[void]$lines.Add("")
[void]$lines.Add("### Phase C — FRIGO Produktion")
[void]$lines.Add("- C1: IT-UEBERGABE 5 Entscheidungen")
[void]$lines.Add("- C2: frigohub.bak deduplizieren")
[void]$lines.Add("")
[void]$lines.Add("### Parallel (nicht blockierend)")
[void]$lines.Add("- BRAIN_FIX #7 Kimi — nur wenn Council nicht escalate-majority")
[void]$lines.Add("- webagent Option2 Cutover auf neuem PC via first_login_wizard")
[void]$lines.Add("")
[void]$lines.Add("## Nicht anfassen")
[void]$lines.Add("- webagent/data/profiles/_archive (Backups)")
[void]$lines.Add("- webagent/data/profiles/shared (aktives Profil)")
[void]$lines.Add("")
[void]$lines.Add("## Naechste Schritte")
[void]$lines.Add("1. Vibe formal approved/rejected (deputy)")
[void]$lines.Add("2. Storax audio: Freigabe Phase B")
[void]$lines.Add("3. Grok fuehrt Phase A aus")

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outPath, ($lines -join "`n"), $utf8)
Write-Host "[finalize] -> $outPath (consensus=$consensus)" -ForegroundColor Green
Write-Output $outPath