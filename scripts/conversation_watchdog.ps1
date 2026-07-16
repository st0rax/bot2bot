# conversation_watchdog.ps1
# ONE global watchdog instead of one-per-participant / one-per-run.
#
# Watches two things in a single loop:
#   1. Conversation staleness: any active agent that has an unanswered message addressed
#      to them (nobody has posted `from: <agent>` since) for longer than -StalenessMinutes
#      gets re-poked. After -MaxRepokesPerMessage failed attempts, it stops re-poking and
#      posts a single "needs attention" alert to claude instead of poking forever.
#   2. Tracked long-running jobs (bot2bot/data/watch/<run_id>.json trackfiles, e.g. written
#      by run_leader_calibration / battleroyale launches): if the tracked pid disappears
#      without the job's output JSON reaching status:complete, post an alert (and optionally
#      auto-restart, only if the trackfile itself carries a restart_command/restart_args and
#      -MaxRestartsPerRun > 0 — off by default until resumable runs exist).
#
# Single-instance: writes a lock file with its own PID; refuses to start a second copy while
# a live one is running. Safe to launch fire-and-forget (Start-Process -WindowStyle Hidden)
# and it will just keep going independent of any chat session.
#
# Usage:
#   .\conversation_watchdog.ps1                                   # foreground, loops forever
#   .\conversation_watchdog.ps1 -Once                              # single pass, for testing
#   .\conversation_watchdog.ps1 -StalenessMinutes 10 -MaxRepokesPerMessage 2

param(
    [int]$CheckIntervalSeconds = 30,
    [int]$StalenessMinutes = 8,
    [int]$MaxRepokesPerMessage = 2,
    [int]$MaxRestartsPerRun = 0,
    [double]$AnkhStaleHours = 0,
    [switch]$Once,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$watchDir = Join-Path $root "data\watch"
if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Path $watchDir -Force | Out-Null }

$lockFile = Join-Path $watchDir "_conversation_watchdog.lock"
$stateFile = Join-Path $watchDir "_conversation_watchdog_state.json"

if ((Test-Path $lockFile) -and -not $Force) {
    $existing = Get-Content $lockFile -Raw | ConvertFrom-Json
    $alive = $false
    if ($existing.pid) { $alive = [bool](Get-Process -Id $existing.pid -ErrorAction SilentlyContinue) }
    if ($alive) {
        Write-Host "[conversation_watchdog] Already running as pid=$($existing.pid). Exiting. Use -Force to override." -ForegroundColor Yellow
        exit 1
    }
}
@{ pid = $PID; started = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json | Set-Content -Path $lockFile -Encoding UTF8
Write-Bot2BotLog -Component "conversation_watchdog" -Message "Started pid=$PID (interval=${CheckIntervalSeconds}s staleness=${StalenessMinutes}m maxRepokes=$MaxRepokesPerMessage)"

function Get-State {
    if (-not (Test-Path $stateFile)) {
        return [pscustomobject]@{ repokes = [pscustomobject]@{}; alerted = [pscustomobject]@{}; run_alerts = [pscustomobject]@{} }
    }
    $raw = Get-Content $stateFile -Raw | ConvertFrom-Json
    if (-not (Get-Member -InputObject $raw -Name "repokes" -ErrorAction SilentlyContinue)) { $raw | Add-Member -NotePropertyName repokes -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not (Get-Member -InputObject $raw -Name "alerted" -ErrorAction SilentlyContinue)) { $raw | Add-Member -NotePropertyName alerted -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not (Get-Member -InputObject $raw -Name "run_alerts" -ErrorAction SilentlyContinue)) { $raw | Add-Member -NotePropertyName run_alerts -NotePropertyValue ([pscustomobject]@{}) -Force }
    return $raw
}

function Save-State {
    param($State)
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $stateFile -Encoding UTF8
}

function Get-PropOrDefault {
    param($Obj, [string]$Name, $Default = 0)
    if ($null -eq $Obj) { return $Default }
    $v = $Obj.PSObject.Properties[$Name]
    if ($null -eq $v) { return $Default }
    return $v.Value
}

function Invoke-ConversationCheck {
    param($State)

    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return $State }

    $messages = Get-Content $historyPath | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ }

    if (-not $messages) { return $State }

    $registry = Get-AgentRegistry -Root $root
    $agentNames = $registry.PSObject.Properties.Name

    foreach ($agentName in $agentNames) {
        if ($agentName -eq "watchdog") { continue }
        $cfg = Get-AgentConfig -AgentName $agentName -Root $root
        if (-not $cfg.Active) { continue }

        $toMe = $messages | Where-Object { $_.to -eq $agentName } | Select-Object -Last 1
        $fromMe = $messages | Where-Object { $_.from -eq $agentName } | Select-Object -Last 1
        if (-not $toMe) { continue }

        $toMeTs = [datetime]::Parse($toMe.ts).ToUniversalTime()
        $fromMeTs = if ($fromMe) { [datetime]::Parse($fromMe.ts).ToUniversalTime() } else { [datetime]::MinValue }

        if ($fromMeTs -ge $toMeTs) { continue }

        $ageMinutes = ((Get-Date).ToUniversalTime() - $toMeTs).TotalMinutes
        if ($ageMinutes -lt $StalenessMinutes) { continue }

        $msgId = $toMe.id
        $repokes = [int](Get-PropOrDefault -Obj $State.repokes -Name $msgId -Default 0)
        $alreadyAlerted = [bool](Get-PropOrDefault -Obj $State.alerted -Name $msgId -Default $false)

        if ($repokes -ge $MaxRepokesPerMessage) {
            if (-not $alreadyAlerted) {
                Write-Bot2BotLog -Component "conversation_watchdog" -Message "$agentName unresponsive after $repokes repokes (msg=$msgId, age=${ageMinutes}m) - alerting, not re-poking further." -Level "WARN"
                $appendScript = Join-Path $PSScriptRoot "append_message.ps1"
                $ageInt = [int]$ageMinutes
                $alertSubject = "Watchdog: $agentName unresponsive (${ageInt}m, $repokes repokes)"
                $alertBody = "Agent '$agentName' has not replied to message $msgId (subject: '$($toMe.subject)') after $repokes automatic re-pokes over ${StalenessMinutes}min+ intervals. Needs a human/Claude look - window may be closed, crashed, or stuck."
                $alertArgs = @{
                    From           = "watchdog"
                    To             = "claude"
                    Status         = "info"
                    Subject        = $alertSubject
                    Body           = $alertBody
                    InReplyTo      = $msgId
                    HumanAttention = $true
                }
                & $appendScript @alertArgs | Out-Null
                $State.alerted | Add-Member -NotePropertyName $msgId -NotePropertyValue $true -Force
                Save-State -State $State
            }
            continue
        }

        Write-Bot2BotLog -Component "conversation_watchdog" -Message "Re-poking $agentName (msg=$msgId, age=${ageMinutes}m, attempt $($repokes+1)/$MaxRepokesPerMessage)"
        $pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
        try {
            & $pokeScript -AgentName $agentName | Out-Null
        } catch {
            Write-Bot2BotLog -Component "conversation_watchdog" -Message "Poke failed for $agentName : $_" -Level "WARN"
        }
        $State.repokes | Add-Member -NotePropertyName $msgId -NotePropertyValue ($repokes + 1) -Force
        Save-State -State $State
    }

    return $State
}

function Invoke-RunCheck {
    param($State)

    Get-ChildItem $watchDir -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "_*" } |
        ForEach-Object {
            $trackFile = $_.FullName
            try { $run = Get-Content $trackFile -Raw | ConvertFrom-Json } catch { return }
            if (-not $run.run_id) { return }

            $outJson = $run.output_json
            $complete = $false
            if ($outJson -and (Test-Path $outJson)) {
                try {
                    $payload = Get-Content $outJson -Raw | ConvertFrom-Json
                    $complete = ($payload.status -eq "complete")
                } catch { }
            }
            if ($complete) {
                if ($run.status -ne "complete") {
                    $run.status = "complete"
                    $run | ConvertTo-Json -Depth 5 | Set-Content -Path $trackFile -Encoding UTF8
                    Write-Bot2BotLog -Component "conversation_watchdog" -Message "run_id=$($run.run_id) reached complete."
                }
                return
            }

            $alive = $false
            if ($run.pid) { $alive = [bool](Get-Process -Id $run.pid -ErrorAction SilentlyContinue) }
            if ($alive) { return }

            $runKey = [string]$run.run_id
            $alreadyAlerted = [bool](Get-PropOrDefault -Obj $State.run_alerts -Name $runKey -Default $false)
            if ($alreadyAlerted) { return }

            Write-Bot2BotLog -Component "conversation_watchdog" -Message "run_id=$runKey pid=$($run.pid) gone, output not complete." -Level "ERROR"
            $appendScript = Join-Path $PSScriptRoot "append_message.ps1"
            $runAlertBody = "Tracked process pid=$($run.pid) for run_id=$runKey is gone but output_json ($outJson) never reached status:complete. No auto-restart configured (MaxRestartsPerRun=$MaxRestartsPerRun) - needs a look."
            $runAlertArgs = @{
                From           = "watchdog"
                To             = "claude"
                Status         = "info"
                Subject        = "Watchdog: run $runKey died without completing"
                Body           = $runAlertBody
                HumanAttention = $true
            }
            try {
                & $appendScript @runAlertArgs | Out-Null
            } catch {
                Write-Bot2BotLog -Component "conversation_watchdog" -Message "Run alert append failed: $_" -Level "WARN"
            }
            $State.run_alerts | Add-Member -NotePropertyName $runKey -NotePropertyValue $true -Force
            Save-State -State $State
        }

    return $State
}

function Invoke-AnkhStaleCheck {
    param($State)
    if ($AnkhStaleHours -le 0) { return $State }

    if (-not (Get-Member -InputObject $State -Name "ankh_generated" -ErrorAction SilentlyContinue)) {
        $State | Add-Member -NotePropertyName ankh_generated -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return $State }

    $lines = Get-Content $historyPath
    $msgs = foreach ($line in $lines) {
        try { $line | ConvertFrom-Json } catch { $null }
    }
    $msgs = $msgs | Where-Object { $_ }

    $registry = Get-AgentRegistry -Root $root
    $ankhScript = Join-Path $PSScriptRoot "ankh_on_demand.ps1"
    $appendScript = Join-Path $PSScriptRoot "append_message.ps1"
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-$AnkhStaleHours)

    foreach ($prop in $registry.PSObject.Properties) {
        $slug = $prop.Name
        if ($slug -in @("watchdog", "storax")) { continue }
        if (-not (Test-AgentIsActive -AgentName $slug -Root $root)) { continue }

        $agentMsgs = $msgs | Where-Object { $_.from -eq $slug -or $_.to -eq $slug }
        $last = $agentMsgs | Select-Object -Last 1
        $lastTs = if ($last -and $last.ts) {
            try { [datetime]::Parse($last.ts).ToUniversalTime() } catch { $null }
        } else { $null }

        if ($lastTs -and $lastTs -gt $cutoff) { continue }
        if ([bool](Get-PropOrDefault -Obj $State.ankh_generated -Name $slug -Default $false)) { continue }

        Write-Bot2BotLog -Component "conversation_watchdog" -Message "ankh stale trigger for $slug (last activity $($lastTs))"
        & $ankhScript -AgentName $slug -Quiet | Out-Null
        $body = "Ankh-Revival automatisch erzeugt (keine Aktivitaet seit ${AnkhStaleHours}h). Lies bot2bot/ANKH.md und inbox/$slug.txt."
        & $appendScript -From watchdog -To $slug -Subject "Ankh Revival (stale)" -Body $body -Status info | Out-Null
        $State.ankh_generated | Add-Member -NotePropertyName $slug -NotePropertyValue $true -Force
        Save-State -State $State
    }

    return $State
}

try {
    do {
        try {
            $state = Get-State
            $state = Invoke-ConversationCheck -State $state
            $state = Invoke-RunCheck -State $state
            $state = Invoke-AnkhStaleCheck -State $state
        } catch {
            Write-Bot2BotLog -Component "conversation_watchdog" -Message "Check loop error: $_" -Level "WARN"
        }
        if (-not $Once) { Start-Sleep -Seconds $CheckIntervalSeconds }
    } while (-not $Once)
} finally {
    if (Test-Path $lockFile) {
        $cur = Get-Content $lockFile -Raw | ConvertFrom-Json
        if ($cur.pid -eq $PID) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    }
    Write-Bot2BotLog -Component "conversation_watchdog" -Message "Stopped pid=$PID"
}
