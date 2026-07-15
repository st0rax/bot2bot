# scripts/test_watcher_decisions.ps1
# Unit test for pure Resolve-WatcherActions + Split-WakeCommand (no I/O, no poke).
# Run twice; full output captured to {SCRATCH}/bot2bot-tests.log

. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$Root = Get-Bot2BotRoot

# Fixed fixture: testagent is safemode + has inbox + 1 msg (aligned in registry)
$fixture = @{
    'testagent' = @{
        active = $true
        poll_mode = 'safemode'
        wake_command = 'pwsh -NoProfile -File scripts/wake/window_poke.ps1 --agent testagent'
        inbox_exists = $true
        msg_count = 1
    }
    # chatgpt example with inbox now present
    'chatgpt' = @{
        active = $true
        poll_mode = 'safemode'
        wake_command = 'pwsh -NoProfile -File scripts/wake/window_poke.ps1 --agent chatgpt'
        inbox_exists = $true
        msg_count = 1
    }
}

# Load real registry for other agents (they will be self or inactive)
$reg = Get-AgentRegistry -Root $Root

$actions = Resolve-WatcherActions -Registry $reg -AgentStates $fixture

Write-Host "=== Resolve-WatcherActions results ==="
$actions | ForEach-Object { Write-Host ("{0} {1} {2}" -f $_.action, $_.slug, $_.wake) }

# Assertions
$wakeTest = $actions | Where-Object { $_.action -eq 'SafemodeWake' -and $_.slug -eq 'testagent' }
if (-not $wakeTest) { throw "Expected SafemodeWake for testagent" }
$exe, $args = Split-WakeCommand -WakeCommand $wakeTest.wake
if ($exe -notlike '*pwsh*') { throw "Split exe wrong: $exe" }
if ($args -notcontains '--agent') { throw "Split args missing --agent" }
Write-Host "Split result: exe=$exe args=$($args -join ' ')"

$noInbox = $actions | Where-Object { $_.action -eq 'SafemodeNoInbox' }
# if any, just log (depends on fixture)
Write-Host "Test passed: SafemodeWake + split exercised for fixture agents"

# Also test a self-poll case
$self = $actions | Where-Object { $_.action -eq 'SelfPollSkip' -and $_.slug -eq 'grok' }
if ($self) { Write-Host "SelfPollSkip for grok confirmed" }

exit 0