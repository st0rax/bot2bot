# suchtrupp.ps1 — Projekt-Recon (webagent + bot2bot)
#
#   .\suchtrupp.ps1              # Report nach data/suchtrupp_report.md
#   .\suchtrupp.ps1 -NotifyStorax  # + Audio an Storax

param(
    [switch]$NotifyStorax,
    [switch]$RestartDaemons
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagent = Join-Path (Split-Path $root -Parent) "webagent"
$outPath = Join-Path $root "data\suchtrupp_report.md"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Get-DaemonLockStatus {
    param([string]$WatchDir)
    $locks = Get-ChildItem $WatchDir -Filter "_*.lock" -ErrorAction SilentlyContinue
    $rows = @()
    foreach ($lock in $locks) {
        try {
            $j = Get-Content $lock.FullName -Raw | ConvertFrom-Json
            $alive = $false
            if ($j.pid) { $alive = [bool](Get-Process -Id $j.pid -ErrorAction SilentlyContinue) }
            $rows += [pscustomobject]@{ Lock = $lock.Name; Pid = $j.pid; Alive = $alive }
        } catch { }
    }
    return $rows
}

$daemonRows = Get-DaemonLockStatus -WatchDir (Join-Path $root "data\watch")
$deadLocks = @($daemonRows | Where-Object { -not $_.Alive })

$idx = $null
$idxPath = Join-Path $root "data\leistungsindex.json"
if (Test-Path $idxPath) {
    $idx = Get-Content $idxPath -Raw | ConvertFrom-Json
}

$calRuns = @()
$calDir = Join-Path $webagent "data\leader_calibration\runs"
if (Test-Path $calDir) {
    foreach ($f in Get-ChildItem $calDir -Filter "*.json") {
        try {
            $r = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $invalid = @($r.responses | Where-Object { -not $_.ok }).Count
            $calRuns += [pscustomobject]@{
                Run = $r.run_id
                Status = $r.status
                Invalid = $invalid
                Pairs = @($r.responses).Count
            }
        } catch { }
    }
}

$handoffOpen = @()
$handoffPath = Join-Path $root "HANDOFF.md"
if (Test-Path $handoffPath) {
    $handoffOpen = Select-String -Path $handoffPath -Pattern "^\d+\. \*\*" | ForEach-Object { $_.Line.Trim() }
}

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("# Suchtrupp Report")
[void]$lines.Add("")
[void]$lines.Add("Generated: $stamp")
[void]$lines.Add("")
[void]$lines.Add("## Leistungsindex")
if ($idx) {
    [void]$lines.Add("- storax: $($idx.participants.storax.score)")
    [void]$lines.Add("- vibe: $($idx.participants.vibe.score)")
    [void]$lines.Add("- grok: $($idx.participants.grok.score)")
    [void]$lines.Add("- open_cases: $(@($idx.open_cases).Count)")
} else {
    [void]$lines.Add("- (nicht lesbar)")
}
[void]$lines.Add("")
[void]$lines.Add("## Calibration Runs")
foreach ($c in $calRuns | Sort-Object Run) {
    [void]$lines.Add("- $($c.Run): $($c.Status), pairs=$($c.Pairs), INVALID=$($c.Invalid)")
}
[void]$lines.Add("")
[void]$lines.Add("## Watch Daemons")
foreach ($d in $daemonRows) {
    $state = if ($d.Alive) { "alive" } else { "DEAD" }
    [void]$lines.Add("- $($d.Lock): pid=$($d.Pid) $state")
}
[void]$lines.Add("")
[void]$lines.Add("## HANDOFF Open Items")
foreach ($h in $handoffOpen) { [void]$lines.Add("- $h") }
[void]$lines.Add("")
[void]$lines.Add("## Key Paths")
[void]$lines.Add("- bot2bot: $root")
[void]$lines.Add("- webagent: $webagent")
[void]$lines.Add("- history: history/conversation.jsonl")
[void]$lines.Add("- deputy: data/claude_deputy.json")
[void]$lines.Add("- ankh: ANKH.md (revival briefing)")
[void]$lines.Add("")
[void]$lines.Add("## Prioritaeten (WEBAGENT-ONLY)")
[void]$lines.Add("1. Installer zweiter PC: webagent-suite + first_login_wizard + verify -Strict")
[void]$lines.Add("2. BRAIN_FIX #7 Kimi composer (webagent/src/webagent/brains/kimi.py)")
[void]$lines.Add("3. Option2 shared-browser Cutover (Operator)")
[void]$lines.Add("4. PAUSIERT: web2terminal, FRIGO, consensus, neue Kalibrierung")

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outPath, ($lines -join "`n"), $utf8)
Write-Bot2BotLog -Component "suchtrupp" -Message "Report -> $outPath (dead_locks=$($deadLocks.Count))"

if ($RestartDaemons) {
    foreach ($d in $deadLocks) {
        $lockPath = Join-Path (Join-Path $root "data\watch") $d.Lock
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    }
    $scripts = @(
        "vibe_response_subagent.ps1",
        "mediator_chatgpt_watch.ps1",
        "conversation_watchdog.ps1",
        "watch_vibe_for_grok.ps1"
    )
    foreach ($s in $scripts) {
        $p = Join-Path $PSScriptRoot $s
        if (Test-Path $p) {
            Start-Process pwsh -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $p) -WindowStyle Hidden | Out-Null
        }
    }
    Write-Bot2BotLog -Component "suchtrupp" -Message "Daemons restart requested"
}

if ($NotifyStorax) {
    $append = Join-Path $PSScriptRoot "append_message.ps1"
    $body = "Suchtrupp Report fertig. $($deadLocks.Count) tote Daemon-Locks. Report unter data/suchtrupp_report.md. Audio-only aktiv."
    & $append -From grok -To storax -Subject "Suchtrupp Report bereit" -Body $body -Status info -HumanAttention
}

Write-Host "[suchtrupp] OK -> $outPath" -ForegroundColor Green