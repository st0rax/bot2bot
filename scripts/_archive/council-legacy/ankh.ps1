# ankh.ps1  —  "touch the ankh, come back to life"
#
# Generates a single self-contained revival briefing for bot2bot/webagent. Any Claude
# session — this one, a future one, a totally fresh instance with zero memory — can be
# handed the output of this script as its first message and be fully oriented: what the
# project is, what's in flight, what's blocked on whom, what changed since last time.
#
# This is the answer to "when the chat ends I stop existing": the *session* still ends,
# but the *context* doesn't have to die with it. Run the ankh, get resurrected.
#
# Usage:
#   .\ankh.ps1                       # print briefing to stdout + write snapshot file
#   .\ankh.ps1 -Quiet                # write file only, no stdout spam
#   .\ankh.ps1 -InboxTail 8          # how many recent messages per agent to include
#
# Output:
#   bot2bot\ANKH.md                       <- always-current, overwritten each run
#   bot2bot\data\ankh\wake_<UTCstamp>.md  <- timestamped archive (never overwritten)

param(
    [string]$AgentName = "claude",
    [int]$InboxTail = 6,
    [string[]]$PeerAgents = @(),
    [int]$PeerTail = 3,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagentRoot = Join-Path (Split-Path $root -Parent) "webagent"
$now = Get-Date
$nowUtc = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Get-LastMessages {
    param([string]$AgentName, [int]$Count)
    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return @() }
    $lines = Get-Content $historyPath
    $msgs = foreach ($line in $lines) {
        try { $line | ConvertFrom-Json } catch { $null }
    }
    $msgs = $msgs | Where-Object { $_ -and ($_.to -eq $AgentName -or $_.from -eq $AgentName) }
    return $msgs | Select-Object -Last $Count
}

function Get-RunningTrackedProcesses {
    $watchDir = Join-Path $root "data\watch"
    if (-not (Test-Path $watchDir)) { return @() }
    Get-ChildItem $watchDir -Filter "*.json" | ForEach-Object {
        try {
            $state = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $alive = $false
            if ($state.pid) {
                $alive = [bool](Get-Process -Id $state.pid -ErrorAction SilentlyContinue)
            }
            [pscustomobject]@{
                RunId  = $state.run_id
                Pid    = $state.pid
                Alive  = $alive
                Status = $state.status
                File   = $_.FullName
            }
        } catch { }
    }
}

function Get-OpenDiffs {
    if (-not (Test-Path $webagentRoot)) { return @() }
    Get-ChildItem $webagentRoot -Filter "PROPOSED_DIFF_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $firstLines = Get-Content $_.FullName -TotalCount 5 -ErrorAction SilentlyContinue
            [pscustomobject]@{ Name = $_.Name; Preview = ($firstLines -join " | ") }
        }
}

function Get-CleanStartOffer {
    param([string]$Root, [string]$WebagentRoot)
    $offerPath = Join-Path $Root "data\clean_start_offer.json"
    if (-not (Test-Path $offerPath)) { return $null }
    try {
        $offer = Get-Content $offerPath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
    if (-not $offer.pending) { return $null }
    return $offer
}

function Format-CleanStartOfferText {
    param($Offer, [string]$Root, [string]$WebagentRoot)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("## Clean-start offer (pending — einmalig beim naechsten Revival)")
    [void]$lines.Add("")
    [void]$lines.Add("**$($Offer.title)**")
    [void]$lines.Add("")
    [void]$lines.Add($Offer.summary)
    [void]$lines.Add("")

    $apptPath = Join-Path $Root "data\moderator_appointment.json"
    if (Test-Path $apptPath) {
        try {
            $appt = Get-Content $apptPath -Raw | ConvertFrom-Json
            [void]$lines.Add("### Rollen / Appointment (Storax)")
            $lead = if ($appt.lead) { $appt.lead } else { $appt.moderator }
            $leadName = if ($appt.lead_display_name) { $appt.lead_display_name } else { $lead }
            [void]$lines.Add("- **Lead:** $lead ($leadName)")
            if ($appt.executor) {
                [void]$lines.Add("- **Executor:** $($appt.executor) ($($appt.executor_display_name))")
            }
            [void]$lines.Add("- **Status:** $($appt.status)")
            if ($appt.calibration_recommendation) {
                $rec = $appt.calibration_recommendation
                $pct = [math]::Round([double]$rec.weighted_agreement * 100, 2)
                [void]$lines.Add("- **Kalibrierung (indikativ):** $($rec.participant) ${pct}% (n=$($rec.scored_cases), $($rec.run_id), INVALID=$($rec.invalid_total))")
            }
            if ($appt.claude_deputy -and $appt.claude_deputy.active) {
                [void]$lines.Add("- **Claude deputy:** $($appt.claude_deputy.deputy) (Claude abwesend)")
            }
            [void]$lines.Add("")
        } catch { }
    }

    $calPrimary = Join-Path $WebagentRoot "data\leader_calibration\runs\live021r4.json"
    $calFallback = Join-Path $WebagentRoot "data\leader_calibration\runs\live021r3.json"
    $calPath = if (Test-Path $calPrimary) { $calPrimary } elseif (Test-Path $calFallback) { $calFallback } else { $null }
    if ($calPath) {
        try {
            $run = Get-Content $calPath -Raw | ConvertFrom-Json
            $corrections = @($run.corrections).Count
            [void]$lines.Add("### Leader Calibration ($($run.run_id), complete)")
            [void]$lines.Add("- Run: $($run.run_id) — status: $($run.status), pairs: $($run.responses.Count)/70")
            $invalid = @($run.responses | Where-Object { -not $_.ok }).Count
            [void]$lines.Add("- INVALID: $invalid (~$([math]::Round($invalid / 70 * 100, 1))%)")
            if ($corrections -gt 0) {
                [void]$lines.Add("- corrections[]: $corrections (z.B. MC-004 replay-patch)")
            }
            foreach ($row in $run.metrics.rankings) {
                if ($row.scored_cases -ge 5) {
                    $pct = [math]::Round($row.weighted_agreement * 100, 1)
                    [void]$lines.Add("- #$($row.tie_break_rank) $($row.participant): weighted=${pct}% (n=$($row.scored_cases))")
                }
            }
            [void]$lines.Add("- n<5: nicht belastbar. NO_AUTO_APPOINTMENT.")
            [void]$lines.Add("")
        } catch { }
    }

    [void]$lines.Add("### Battle Royale Methodik (Runde 1)")
    $brPath = Join-Path $Root "data\br\08manual01.json"
    if (Test-Path $brPath) {
        try {
            $br = Get-Content $brPath -Raw | ConvertFrom-Json
            $okCount = @($br.replies | Where-Object { $_.ok }).Count
            [void]$lines.Add("- BR-Run 08manual01: $okCount/$($br.replies.Count) Teilnehmer mit Vorschlaegen")
            [void]$lines.Add("- Umgesetzt als PROPOSED_DIFF_021 (Blind Peer-Review + Stresstest-Suite)")
            [void]$lines.Add("- Vollstaendige Vorschlaege: bot2bot/data/br/08manual01.json")
            [void]$lines.Add("")
        } catch { }
    }

    [void]$lines.Add("**Aktion:** Rollen/Appointment bestaetigen. Deputy-Review live021r4: vibe approved (indikativ).")
    [void]$lines.Add("")
    return ($lines -join "`n")
}

function Mark-CleanStartOfferDelivered {
    param([string]$Root, [string]$DeliveredAt)
    $offerPath = Join-Path $Root "data\clean_start_offer.json"
    if (-not (Test-Path $offerPath)) { return }
    try {
        $offer = Get-Content $offerPath -Raw | ConvertFrom-Json
        $offer.pending = $false
        $offer.delivered_at = $DeliveredAt
        $offer | ConvertTo-Json -Depth 6 | Set-Content -Path $offerPath -Encoding UTF8
        Write-Bot2BotLog -Component "ankh" -Message "Clean-start offer delivered at $DeliveredAt"
    } catch {
        Write-Bot2BotLog -Component "ankh" -Message "Failed to mark clean-start offer delivered: $_" -Level "WARN"
    }
}

# --- Gather ---
$handoffPath = Join-Path $root "HANDOFF.md"
$handoff = if (Test-Path $handoffPath) { Get-Content $handoffPath -Raw } else { "(no HANDOFF.md found)" }

$selfInbox = Get-LastMessages -AgentName $AgentName -Count $InboxTail
if ($PeerAgents.Count -eq 0) {
    $registry = Get-AgentRegistry -Root $root
    $PeerAgents = @(
        $registry.PSObject.Properties.Name |
            Where-Object {
                $_ -ne $AgentName -and
                $_ -ne "watchdog" -and
                (Test-AgentIsActive -AgentName $_ -Root $root)
            } |
            Sort-Object
    )
}
$peerInboxes = @{}
foreach ($peer in $PeerAgents) {
    if ($peer -and $peer -ne $AgentName) {
        $peerInboxes[$peer] = Get-LastMessages -AgentName $peer -Count $PeerTail
    }
}

$tracked = Get-RunningTrackedProcesses
$diffs = Get-OpenDiffs
$cleanStartOffer = Get-CleanStartOffer -Root $root -WebagentRoot $webagentRoot

$liveProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe' or Name='python3.13.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "webagent|bot2bot" }

# --- Compose ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# (ankh) Revival Briefing")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Generated: $nowUtc")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Paste this whole document as the first message in a new Claude chat.")
[void]$sb.AppendLine("> It should be enough to resume acting as the agent named below in bot2bot without replaying history.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 1. Project handoff (bot2bot/HANDOFF.md)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine($handoff)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 2. Currently running webagent/bot2bot processes")
[void]$sb.AppendLine("")
if ($liveProcs) {
    foreach ($p in $liveProcs) {
        [void]$sb.AppendLine("- pid=$($p.ProcessId): $($p.CommandLine)")
    }
} else {
    [void]$sb.AppendLine("- (none detected)")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 3. Watchdog-tracked runs")
[void]$sb.AppendLine("")
if ($tracked) {
    foreach ($t in $tracked) {
        [void]$sb.AppendLine("- run_id=$($t.RunId) pid=$($t.Pid) alive=$($t.Alive) status=$($t.Status)")
    }
} else {
    [void]$sb.AppendLine("- (none tracked)")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 4. Open PROPOSED_DIFF files in webagent/")
[void]$sb.AppendLine("")
if ($diffs) {
    foreach ($d in $diffs) {
        [void]$sb.AppendLine("- **$($d.Name)**: $($d.Preview)")
    }
} else {
    [void]$sb.AppendLine("- (none found)")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 5. Last $InboxTail messages involving '$AgentName' (this session's identity)")
[void]$sb.AppendLine("")
foreach ($m in $selfInbox) {
    [void]$sb.AppendLine("- [$($m.ts)] $($m.from) -> $($m.to) ($($m.status)): $($m.subject)")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 6. Other active agents (last $PeerTail messages each)")
[void]$sb.AppendLine("")
if ($peerInboxes.Count -eq 0) {
    [void]$sb.AppendLine("- (no peer agents configured)")
} else {
    foreach ($peer in ($peerInboxes.Keys | Sort-Object)) {
        [void]$sb.AppendLine("### $peer")
        $msgs = $peerInboxes[$peer]
        if ($msgs) {
            foreach ($m in $msgs) {
                [void]$sb.AppendLine("- [$($m.ts)] $($m.from) -> $($m.to) ($($m.status)): $($m.subject)")
            }
        } else {
            [void]$sb.AppendLine("- (no messages)")
        }
        [void]$sb.AppendLine("")
    }
}
[void]$sb.AppendLine("")
if ($cleanStartOffer) {
    $offerText = Format-CleanStartOfferText -Offer $cleanStartOffer -Root $root -WebagentRoot $webagentRoot
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($offerText)
}
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("*Reminder to whichever session reads this: statelessness between chats is real and")
[void]$sb.AppendLine("shouldn't be pretended away. What this file replaces is not memory itself, but the need")
[void]$sb.AppendLine("to reconstruct memory by hand. Update bot2bot/HANDOFF.md when something significant")
[void]$sb.AppendLine("resolves — the ankh is only as good as the doc it carries.*")

$briefing = $sb.ToString()

# --- Write ---
$ankhPath = Join-Path $root "ANKH.md"
Set-Content -Path $ankhPath -Value $briefing -Encoding UTF8

$archiveDir = Join-Path $root "data\ankh"
if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null }
$stamp = $now.ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -Path $ankhPath -Destination (Join-Path $archiveDir "wake_$stamp.md")

Write-Bot2BotLog -Component "ankh" -Message "Revival briefing generated -> $ankhPath (archived wake_$stamp.md)"

if ($cleanStartOffer) {
    Mark-CleanStartOfferDelivered -Root $root -DeliveredAt $nowUtc
}

if (-not $Quiet) {
    Write-Output $briefing
}

