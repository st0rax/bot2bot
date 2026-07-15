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

# Build per-slug state for pure resolver (no silent continues)
$states = @{}
foreach ($slug in $registry.PSObject.Properties.Name) {
    $cfg = Get-AgentConfig -AgentName $slug -Root $Root
    $inboxPath = Join-Path $agentsDir "$slug\inbox"
    $exists = Test-Path $inboxPath
    $cnt = 0
    if ($exists) {
        $cnt = (Get-ChildItem $inboxPath -Filter *.msg* -ErrorAction SilentlyContinue | Measure-Object).Count
    }
    $states[$slug] = @{
        active = $cfg.Active
        poll_mode = $cfg.PollMode
        wake_command = $cfg.WakeCommand
        inbox_exists = $exists
        msg_count = $cnt
    }
}

$actions = Resolve-WatcherActions -Registry $registry -AgentStates $states

foreach ($a in $actions) {
    switch ($a.action) {
        'SelfPollSkip' { Write-Host "[watcher] $($a.slug) : self-poll (skipped)" }
        'SafemodeNoInbox' { Write-Host "[watcher] $($a.slug) : safemode but no inbox dir" }
        'SafemodeNoMsgs' { Write-Host "[watcher] $($a.slug) : safemode no new msgs" }
        'SafemodeNoWakeCommand' { Write-Host "[watcher] $($a.slug) : safemode but no wake_command" }
        'SafemodeWake' {
            Write-Host "[watcher] $($a.slug) safemode: $($a.count) new; wake=$($a.wake)"
            if (-not $DryRun) {
                $exe, $args = Split-WakeCommand -WakeCommand $a.wake
                if ($exe) {
                    & $exe $args 2>&1 | Out-Null
                }
            }
        }
        default { Write-Host "[watcher] $($a.slug) : $($a.action)" }
    }
}

Write-Host "[watcher] done"
