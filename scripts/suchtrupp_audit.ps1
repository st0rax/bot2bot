# suchtrupp_audit.ps1 — Minutioese Installer-/Projekt-Pruefung
#
#   .\suchtrupp_audit.ps1
#   .\suchtrupp_audit.ps1 -NotifyStorax

param(
    [switch]$NotifyStorax
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagent = Join-Path (Split-Path $root -Parent) "webagent"
$desktop = [Environment]::GetFolderPath("Desktop")
$suite = Join-Path $desktop "webagent-suite"
$outPath = Join-Path $root "data\suchtrupp_audit.md"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Get-DirSizeMb {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $sum = (Get-ChildItem $Path -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    return [math]::Round($sum / 1MB, 1)
}

function Get-TopFiles {
    param([string]$Path, [int]$N = 15)
    if (-not (Test-Path $Path)) { return @() }
    Get-ChildItem $Path -File -EA SilentlyContinue |
        Sort-Object Length -Descending |
        Select-Object -First $N |
        ForEach-Object { [PSCustomObject]@{ Name = $_.Name; KB = [math]::Round($_.Length / 1KB, 1) } }
}

$issues = New-Object System.Collections.Generic.List[string]
$ok = New-Object System.Collections.Generic.List[string]

# --- Sizes ---
$waMb = Get-DirSizeMb $webagent
$bbMb = Get-DirSizeMb $root
$suiteMb = Get-DirSizeMb $suite

$waDirs = @{}
if (Test-Path $webagent) {
    Get-ChildItem $webagent -Directory | ForEach-Object {
        $waDirs[$_.Name] = Get-DirSizeMb $_.FullName
    }
}

$profileDirs = @{}
$profilesPath = Join-Path $webagent "data\profiles"
if (Test-Path $profilesPath) {
    Get-ChildItem $profilesPath -Directory | ForEach-Object {
        $profileDirs[$_.Name] = Get-DirSizeMb $_.FullName
    }
}

# --- Suite checks ---
$suiteHasArchive = Test-Path (Join-Path $suite "webagent\data\profiles\_archive")
$suiteHasRuntime = Test-Path (Join-Path $suite "webagent\runtime")
$suiteHasShared = Test-Path (Join-Path $suite "webagent\data\profiles\shared\Default")
$suiteInstallPs1 = Join-Path $suite "INSTALL.ps1"
$suiteSkipsCopy = $false
if (Test-Path $suiteInstallPs1) {
    $installText = Get-Content $suiteInstallPs1 -Raw
    $suiteSkipsCopy = $installText -match "ueberspringe Kopie"
}

# --- Script checks ---
$pkgScript = Join-Path $PSScriptRoot "package_release.ps1"
$pkgHasXf = $false
$pkgExcludesArchive = $false
if (Test-Path $pkgScript) {
    $pkgText = Get-Content $pkgScript -Raw
    $pkgHasXf = $pkgText -match '/XF'
    $pkgExcludesArchive = $pkgText -match '_archive'
}

$verifyScript = Join-Path $PSScriptRoot "verify_install.ps1"
$verifyHasStrict = $false
$verifyHasAllowEmpty = $false
if (Test-Path $verifyScript) {
    $vText = Get-Content $verifyScript -Raw
    $verifyHasStrict = $vText -match '\-Strict'
    $verifyHasAllowEmpty = $vText -match 'allow-empty-profile'
}

# --- Root clutter ---
$clutterPatterns = @("GROK_*", "CLAUDE_*", "PROPOSED_DIFF_*", "debug_*.png", "ich_bin_ein_opfer.txt")
$clutterCount = 0
if (Test-Path $webagent) {
    foreach ($pat in $clutterPatterns) {
        $clutterCount += @(Get-ChildItem $webagent -Filter $pat -File -EA SilentlyContinue).Count
    }
}

# --- Dev tests ---
$pytestOk = $null
$pytestCount = $null
$venvPy = Join-Path $webagent "venv\Scripts\python.exe"
if (Test-Path $venvPy) {
    Push-Location $webagent
    $env:PYTHONPATH = "src"
    try {
        $out = & $venvPy -m pytest tests/test_protocol.py tests/test_loop_guard.py tests/test_brains_health_cli.py -q --tb=no 2>&1
        $pytestOk = ($LASTEXITCODE -eq 0)
        if ($out -match '(\d+) passed') { $pytestCount = $Matches[1] }
    } catch { $pytestOk = $false }
    finally { Pop-Location }
}

# --- Issue classification ---
if ($suiteMb -gt 500) {
    [void]$issues.Add("BLOCKER: webagent-suite ist ${suiteMb}MB (Ziel <100MB ohne Profil)")
}
if ($suiteHasArchive) {
    [void]$issues.Add("BLOCKER: Suite enthaelt data/profiles/_archive (~2.3GB Muell)")
}
if ($suiteHasRuntime) {
    [void]$issues.Add("BLOCKER: Suite enthaelt runtime/ (~700MB Playwright-Cache, gehoert nicht ins Paket)")
}
if ($suiteSkipsCopy) {
    [void]$issues.Add("BLOCKER: INSTALL.ps1 ueberspringt Kopie wenn Ziel existiert (stale Upgrade)")
}
if ($suiteHasShared) {
    [void]$issues.Add("WARN: Suite enthaelt eingeloggtes Chrome-Profil (Privacy/Portabilitaet)")
}

$archMb = if ($profileDirs.ContainsKey("_archive")) { $profileDirs["_archive"] } else { 0 }
$sharedMb = if ($profileDirs.ContainsKey("shared")) { $profileDirs["shared"] } else { 0 }
if ($archMb -gt 100) {
    [void]$issues.Add("WARN: Dev-Tree _archive=${archMb}MB — nicht fuer Release kopieren")
}
if ($sharedMb -gt 100) {
    [void]$issues.Add("INFO: Dev-Tree shared=${sharedMb}MB — nur mit -IncludeProfile shippen")
}
if ($clutterCount -gt 50) {
    [void]$issues.Add("WARN: $clutterCount Clutter-Dateien im webagent-Root (debug PNGs, GROK/CLAUDE Diffs)")
}

if ($pkgHasXf) { [void]$ok.Add("package_release.ps1: /XF fuer debug_*.png") } else {
    [void]$issues.Add("FIX: package_release braucht robocopy /XF fuer debug PNGs")
}
if ($pkgExcludesArchive) { [void]$ok.Add("package_release.ps1: _archive ausgeschlossen") } else {
    [void]$issues.Add("FIX: package_release muss _archive ausschliessen")
}
if ($verifyHasStrict -and $verifyHasAllowEmpty) {
    [void]$ok.Add("verify_install.ps1: -Strict + --allow-empty-profile")
} else {
    [void]$issues.Add("FIX: verify_install braucht -Strict und lenient brains-health")
}

if ($pytestOk) { [void]$ok.Add("Dev smoke tests: $pytestCount passed") }
else { [void]$issues.Add("WARN: Dev smoke tests fehlgeschlagen") }

# --- Verdict ---
$blockers = @($issues | Where-Object { $_ -match '^BLOCKER' })
$verdict = if ($blockers.Count -gt 0) {
    "NICHT BEREIT fuer frisches System (ohne Rebuild)"
} elseif ($issues.Count -gt 0) {
    "BEDINGT BEREIT (Warnungen beachten)"
} else {
    "BEREIT fuer frisches System"
}

# --- Report ---
$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("# Suchtrupp Audit — Installer & Projekt")
[void]$lines.Add("")
[void]$lines.Add("Generated: $stamp")
[void]$lines.Add("")
[void]$lines.Add("## Urteil")
[void]$lines.Add("**$verdict**")
[void]$lines.Add("")
[void]$lines.Add("## Groessen")
[void]$lines.Add("| Pfad | MB |")
[void]$lines.Add("|------|-----|")
[void]$lines.Add("| webagent (dev) | $waMb |")
[void]$lines.Add("| bot2bot (dev) | $bbMb |")
[void]$lines.Add("| webagent-suite | $(if ($suiteMb) { $suiteMb } else { 'fehlt' }) |")
[void]$lines.Add("")
[void]$lines.Add("### webagent Top-Verzeichnisse")
foreach ($kv in ($waDirs.GetEnumerator() | Sort-Object { $_.Value } -Descending)) {
    [void]$lines.Add("- $($kv.Key): $($kv.Value) MB")
}
[void]$lines.Add("")
[void]$lines.Add("### data/profiles")
foreach ($kv in ($profileDirs.GetEnumerator() | Sort-Object { $_.Value } -Descending)) {
    [void]$lines.Add("- $($kv.Key): $($kv.Value) MB")
}
[void]$lines.Add("")
[void]$lines.Add("## Suite-Inhalt")
[void]$lines.Add("- _archive in suite: $suiteHasArchive")
[void]$lines.Add("- runtime in suite: $suiteHasRuntime")
[void]$lines.Add("- logged-in shared/Default: $suiteHasShared")
[void]$lines.Add("- INSTALL.ps1 skip-copy bug: $suiteSkipsCopy")
[void]$lines.Add("")
[void]$lines.Add("## Blocker / Issues ($($issues.Count))")
foreach ($i in $issues) { [void]$lines.Add("- $i") }
[void]$lines.Add("")
[void]$lines.Add("## OK ($($ok.Count))")
foreach ($o in $ok) { [void]$lines.Add("- $o") }
[void]$lines.Add("")
[void]$lines.Add("## Root-Clutter (Top debug PNGs)")
foreach ($f in (Get-TopFiles $webagent 8)) {
    [void]$lines.Add("- $($f.Name): $($f.KB) KB")
}
[void]$lines.Add("")
[void]$lines.Add("## Frische-Installation Ablauf (wenn gefixt)")
[void]$lines.Add("1. pwsh -File INSTALL.ps1 -NonInteractive")
[void]$lines.Add("2. verify_install.ps1 (lenient, leeres Profil OK)")
[void]$lines.Add("3. webagent.bat login --brain chatgpt")
[void]$lines.Add("4. verify_install.ps1 -Strict")
[void]$lines.Add("")
[void]$lines.Add("## Voraussetzungen neues System")
[void]$lines.Add("- Windows 10/11, Python 3.11+, **pwsh 7**, Internet")
[void]$lines.Add("- Kein Windows PowerShell 5.1 allein")
[void]$lines.Add("- Manueller Browser-Login pro Brain noetig (ohne -IncludeProfile)")

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outPath, ($lines -join "`n"), $utf8)
Write-Bot2BotLog -Component "suchtrupp_audit" -Message "Audit -> $outPath verdict=$verdict blockers=$($blockers.Count)"

if ($NotifyStorax) {
    $msgPath = Join-Path $root "data\msg_storax_audit.txt"
    @"
Storax, Suchtrupp-Audit fertig.

Urteil: $verdict
Suite-Groesse: $(if ($suiteMb) { "${suiteMb}MB" } else { 'fehlt' })
Blocker: $($blockers.Count)

$(if ($blockers.Count -gt 0) { "Hauptproblem: " + ($blockers[0] -replace '^BLOCKER: ','') } else { "Installer-Skripte sind gefixt; Lean-Rebuild noetig." })

Report: data/suchtrupp_audit.md
"@ | Set-Content $msgPath -Encoding UTF8
    & (Join-Path $PSScriptRoot "append_message.ps1") `
        -From grok -To storax -Subject "Suchtrupp Audit" `
        -BodyPath $msgPath -Status info -HumanAttention
}

Write-Host "[suchtrupp_audit] $verdict" -ForegroundColor $(if ($blockers.Count) { "Red" } else { "Green" })
Write-Host "[suchtrupp_audit] -> $outPath" -ForegroundColor Cyan
if ($blockers.Count) { exit 1 }