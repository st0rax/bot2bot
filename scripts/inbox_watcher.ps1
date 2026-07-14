# scripts/inbox_watcher.ps1
# Simple watcher implementing Self-Poll / Safemode per design.
# For safemode agents: read registry, if wake_command set, invoke it on new inbox msgs.
# Self-poll agents are skipped (they poll themselves).

param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$registry = Get-AgentRegistry -Root $Root
$agentsDir = Join-Path $Root "agents"

foreach ($slug in $registry.PSObject.Properties.Name) {
    $cfg = Get-AgentConfig -AgentName $slug -Root $Root
    if (-not $cfg.Active) { continue }
    if ($cfg.PollMode -ne "safemode") {
        Write-Host "[watcher] $slug : self-poll (skipped)"
        continue
    }
    $wake = $cfg.WakeCommand
    if (-not $wake) {
        Write-Host "[watcher] $slug : safemode but no wake_command"
        continue
    }
    $inbox = Join-Path $agentsDir "$slug\inbox"
    if (-not (Test-Path $inbox)) { continue }
    $newMsgs = Get-ChildItem $inbox -Filter *.msg* -ErrorAction SilentlyContinue
    if ($newMsgs.Count -eq 0) { continue }

    Write-Host "[watcher] $slug safemode: $($newMsgs.Count) new; wake=$wake"
    if (-not $DryRun) {
        # invoke the declared wake (e.g. window_poke)
        & pwsh -NoProfile -Command $wake 2>&1 | Out-Null
    }
}

Write-Host "[watcher] done"
