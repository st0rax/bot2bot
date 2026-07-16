# Cursor vibe->grok monitor: 30 checks x 60s, logs to vibe_subagent_cursor_log.txt
param(
    [int]$MaxChecks = 30,
    [int]$IntervalSeconds = 60,
    [string]$SinceMsgId = "9eb11a9d-e8fe-4cb3-9ee5-ac274d5f95d3"
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$historyPath = Get-HistoryPath -Root $root
$stateFile = Join-Path $root "data\watch\_vibe_response_subagent_state.json"
$logFile = Join-Path $root "data\watch\vibe_subagent_cursor_log.txt"
$idxPath = Join-Path $root "data\leistungsindex.json"
$calPath = "C:\Users\storax\Desktop\webagent\data\leader_calibration\runs\live021r4.json"
$voteScript = Join-Path $PSScriptRoot "vote_penalty.ps1"
$appendScript = Join-Path $PSScriptRoot "append_message.ps1"

function Get-StateObj {
    if (Test-Path $stateFile) {
        return Get-Content $stateFile -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{ last_seen_vibe_msg_id = ""; handled_msg_ids = @(); last_action = ""; last_action_ts = "" }
}

function Save-StateObj($s) {
    $s | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding UTF8
}

function Write-LogLine($line) {
    $ts = (Get-Date).ToUniversalTime().ToString("o")
    "$ts $line" | Add-Content -Path $logFile -Encoding UTF8
}

function Test-Agreement($text) {
    $t = $text.ToLower()
    return $t -match "stimme zu|zustimmung|zustimme|einverstanden|bestaetig|bestätig"
}

function Get-CalCount {
    if (-not (Test-Path $calPath)) { return -1 }
    try {
        $j = Get-Content $calPath -Raw | ConvertFrom-Json
        return @($j.responses).Count
    } catch { return -1 }
}

function Invoke-OneCheck {
    param($checkNum, $state, [ref]$newMsgsFound, [ref]$actionsTaken)

    $calCount = Get-CalCount
    $action = "none"
    $newMsg = $false

    if (-not (Test-Path $historyPath)) {
        Write-LogLine "check=$checkNum cal=$calCount action=no_history"
        return $state
    }

    $messages = @(Get-Content $historyPath | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ })

    $vibeToGrok = @($messages | Where-Object { $_.from -eq "vibe" -and $_.to -eq "grok" })
    $latest = $vibeToGrok | Select-Object -Last 1

    $handled = @()
    if ($state.handled_msg_ids) {
        if ($state.handled_msg_ids -is [string]) { $handled = @($state.handled_msg_ids) }
        else { $handled = @($state.handled_msg_ids) }
    }

    # Process all unhandled since SinceMsgId on check 1, else only new
    $sinceIdx = 0
    for ($i = 0; $i -lt $vibeToGrok.Count; $i++) {
        if ($vibeToGrok[$i].id -eq $SinceMsgId) { $sinceIdx = $i; break }
    }
    $candidates = if ($checkNum -eq 1) {
        $vibeToGrok[$sinceIdx..($vibeToGrok.Count - 1)]
    } else {
        if ($latest -and $latest.id -ne $state.last_seen_vibe_msg_id) { @($latest) } else { @() }
    }

    foreach ($msg in $candidates) {
        if ($msg.id -in $handled) { continue }
        $newMsg = $true
        [void]$newMsgsFound.Value++

        # Auto vote only when agreement clearly targets open penalty case
        if (Test-Path $idxPath) {
            $idx = Get-Content $idxPath -Raw | ConvertFrom-Json
            $openCase = @($idx.open_cases | Where-Object { $_.status -eq "pending_penalty_vote" } | Select-Object -Last 1)
            $text = "$($msg.subject) $($msg.body)".ToLower()
            $targetsCase = $false
            if ($openCase) {
                $cidLower = $openCase.case_id.ToLower()
                $targetsCase = ($text -match $cidLower) -or ($text -match "vote_penalty") -or
                    ($msg.in_reply_to -match "c2542aba")
            }
            if ($openCase -and $targetsCase -and (Test-Agreement $text)) {
                $cid = $openCase.case_id
                $bonus = [int]$openCase.proposed_bonus
                $vMalus = [int]$openCase.proposed_vibe
                try {
                    & $voteScript -CaseId $cid -Voter vibe -StoraxBonus $bonus -VibeMalus $vMalus -Reason "auto: cursor_subagent vibe agreement" | Out-Null
                    $action = "auto_vote:$cid"
                    [void]$actionsTaken.Value++
                } catch {
                    $action = "vote_failed:$cid"
                }
            }
        }

        if ($action -eq "none") {
            $grokReplied = $messages | Where-Object {
                $_.from -eq "grok" -and $_.to -eq "vibe" -and
                ($_.in_reply_to -eq $msg.id -or [datetime]::Parse($_.ts) -ge [datetime]::Parse($msg.ts))
            } | Select-Object -First 1
            if (-not $grokReplied) {
                $action = "needs_grok_reply:$($msg.id)"
            } else {
                $action = "already_answered:$($msg.id)"
            }
        }

        $handled += $msg.id
        $state.last_seen_vibe_msg_id = $msg.id
        $state.handled_msg_ids = $handled | Select-Object -Unique
        $state.last_action = $action
        $state.last_action_ts = (Get-Date).ToUniversalTime().ToString("o")
        Save-StateObj $state
    }

    if (-not $newMsg) {
        $lastId = if ($latest) { $latest.id.Substring(0, 8) } else { "none" }
        Write-LogLine "check=$checkNum cal=$calCount last_vibe=$lastId action=no_new_msg"
    } else {
        Write-LogLine "check=$checkNum cal=$calCount action=$action new_msg=true"
    }

    return $state
}

# Ensure log dir
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$state = Get-StateObj
$newMsgsFound = 0
$actionsTaken = 0
$startCal = Get-CalCount

Write-LogLine "MONITOR_START checks=$MaxChecks interval=${IntervalSeconds}s start_cal=$startCal since=$SinceMsgId"

for ($c = 1; $c -le $MaxChecks; $c++) {
    try {
        $nm = 0; $ac = 0
        $state = Invoke-OneCheck -checkNum $c -state $state -newMsgsFound ([ref]$nm) -actionsTaken ([ref]$ac)
        $newMsgsFound += $nm
        $actionsTaken += $ac
    } catch {
        Write-LogLine "check=$c error=$($_.Exception.Message)"
    }
    if ($c -lt $MaxChecks) { Start-Sleep -Seconds $IntervalSeconds }
}

$endCal = Get-CalCount
Write-LogLine "MONITOR_END checks=$MaxChecks new_msgs=$newMsgsFound actions=$actionsTaken start_cal=$startCal end_cal=$endCal"

# Summary file for cursor pickup
@{
    checks = $MaxChecks
    new_vibe_messages = $newMsgsFound
    actions_taken = $actionsTaken
    start_cal_count = $startCal
    end_cal_count = $endCal
    finished_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content (Join-Path $logDir "_vibe_subagent_cursor_summary.json") -Encoding UTF8