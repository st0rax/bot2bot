# mediator_chatgpt_watch.ps1
# ChatGPT mediator: detect conversation inconsistencies and alert chatgpt.
#
# Usage:
#   .\mediator_chatgpt_watch.ps1 -Once
# Detached:
#   Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','...\mediator_chatgpt_watch.ps1' -WindowStyle Hidden

param(
    [int]$CheckIntervalSeconds = 30,
    [switch]$Once,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$watchDir = Join-Path $root "data\watch"
$mediatorDir = Join-Path $root "data\mediator"
if (-not (Test-Path $mediatorDir)) { New-Item -ItemType Directory -Path $mediatorDir -Force | Out-Null }
$lockFile = Join-Path $watchDir "_mediator_chatgpt_watch.lock"
$stateFile = Join-Path $mediatorDir "watch_state.json"
$appendScript = Join-Path $PSScriptRoot "append_message.ps1"

if ((Test-Path $lockFile) -and -not $Force) {
    $existing = Get-Content $lockFile -Raw | ConvertFrom-Json
    if ($existing.pid -and (Get-Process -Id $existing.pid -ErrorAction SilentlyContinue)) {
        Write-Host "[mediator_watch] Already running pid=$($existing.pid)" -ForegroundColor Yellow
        exit 1
    }
}
@{ pid = $PID; started = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json | Set-Content -Path $lockFile -Encoding UTF8
Write-Bot2BotLog -Component "mediator_watch" -Message "Started pid=$PID interval=${CheckIntervalSeconds}s"

function Get-Messages {
    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return @() }
    return @(Get-Content $historyPath | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ })
}

function Test-HasReplySince {
    param($InboundMsg, $AllMessages, [string]$Responder)
    $inTs = [datetime]::Parse($InboundMsg.ts).ToUniversalTime()
    $reply = $AllMessages |
        Where-Object { $_.from -eq $Responder -and $_.to -eq $InboundMsg.from } |
        Where-Object { [datetime]::Parse($_.ts).ToUniversalTime() -ge $inTs } |
        Select-Object -First 1
    return [bool]$reply
}

function Invoke-LeistungsindexMaintenance {
    $liScript = Join-Path $PSScriptRoot "mediator_leistungsindex.ps1"
    if (-not (Test-Path $liScript)) { return @() }
    try {
        $result = & $liScript -Once -AutoVote -Remind | Select-Object -Last 1
        $out = @()
        if ($result.issues) { $out += @($result.issues) }
        if ($result.actions) { $out += @($result.actions | ForEach-Object { "LI: $_" }) }
        return $out
    } catch {
        Write-Bot2BotLog -Component "mediator_watch" -Message "Leistungsindex maintenance failed: $_" -Level "WARN"
        return @("LEISTUNGSINDEX_MAINT_FAILED: $_")
    }
}

function Invoke-ConsistencyCheck {
    $issues = @()
    $issues += Invoke-LeistungsindexMaintenance
    $messages = Get-Messages

    # 1) Unanswered vibe->grok (last 24h relevant pairs)
    $vibeToGrok = $messages | Where-Object { $_.from -eq "vibe" -and $_.to -eq "grok" } | Select-Object -Last 3
    foreach ($m in $vibeToGrok) {
        if (-not (Test-HasReplySince -InboundMsg $m -AllMessages $messages -Responder "grok")) {
            $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($m.ts).ToUniversalTime()).TotalMinutes
            if ($age -gt 5) {
                $issues += "UNANSWERED vibe->grok: $($m.id) (${age}m) '$($m.subject)'"
            }
        }
    }

    # 2) Unanswered grok->vibe questions
    $grokQuestions = $messages | Where-Object { $_.from -eq "grok" -and $_.to -eq "vibe" -and $_.status -eq "question" } | Select-Object -Last 3
    foreach ($m in $grokQuestions) {
        if (-not (Test-HasReplySince -InboundMsg $m -AllMessages $messages -Responder "vibe")) {
            $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($m.ts).ToUniversalTime()).TotalMinutes
            if ($age -gt 5) {
                $issues += "UNANSWERED grok->vibe question: $($m.id) (${age}m) '$($m.subject)'"
            }
        }
    }

    # 3) Calibration stall hint
    $calPath = "C:\Users\storax\Desktop\webagent\data\leader_calibration\runs\live021r4.json"
    if (Test-Path $calPath) {
        $cal = Get-Content $calPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $n = @($cal.responses).Count
        if ($cal.status -eq "in_progress" -and $n -lt 70) {
            $issues += "CALIBRATION in_progress: live021r4 $n/70"
        }
    }

    return $issues
}

function Get-State {
    if (Test-Path $stateFile) { return Get-Content $stateFile -Raw | ConvertFrom-Json }
    return [pscustomobject]@{ last_alert_hash = ""; last_alert_ts = "" }
}

function Save-State($s) {
    $s | ConvertTo-Json -Depth 3 | Set-Content -Path $stateFile -Encoding UTF8
}

try {
    do {
        try {
            $issues = Invoke-ConsistencyCheck
            if ($issues.Count -gt 0) {
                $hash = ($issues -join "|").GetHashCode()
                $state = Get-State
                if ("$hash" -ne $state.last_alert_hash) {
                    $body = "MEDIATOR CONSISTENCY ALERT`n`n" + ($issues -join "`n") + "`n`nAktion: betroffene Agenten poke/remind; Storax nur bei Eskalation."
                    & $appendScript -From chatgpt -To chatgpt -Subject "Consistency: $($issues.Count) issue(s)" -Body $body -Status info -NoMediatorReport -Poke | Out-Null
                    $state.last_alert_hash = "$hash"
                    $state.last_alert_ts = (Get-Date).ToUniversalTime().ToString("o")
                    Save-State $state
                    Write-Host "[mediator_watch] Alert: $($issues.Count) issues" -ForegroundColor Yellow
                    Write-Bot2BotLog -Component "mediator_watch" -Message "Alert $($issues.Count) issues"
                }
            }
        } catch {
            Write-Bot2BotLog -Component "mediator_watch" -Message "Check error: $_" -Level "WARN"
        }
        if (-not $Once) { Start-Sleep -Seconds $CheckIntervalSeconds }
    } while (-not $Once)
} finally {
    if (Test-Path $lockFile) {
        $cur = Get-Content $lockFile -Raw | ConvertFrom-Json
        if ($cur.pid -eq $PID) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    }
    Write-Bot2BotLog -Component "mediator_watch" -Message "Stopped pid=$PID"
}