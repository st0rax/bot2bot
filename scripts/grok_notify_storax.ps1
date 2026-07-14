# grok_notify_storax.ps1
# Pipeline: parse "benachrichtige storax" instruction -> notify storax -> wait for response.
#
# Usage:
#   .\grok_notify_storax.ps1 -MessagePath "C:\...\inbox\file.msg.txt"
#   .\grok_notify_storax.ps1 -Text "benachrichtige storax: Bitte einloggen"
#   .\grok_notify_storax.ps1 -ProcessPending
#   .\grok_notify_storax.ps1 -WaitOnly -NotifiedAfter "2026-07-14T12:00:00" -ResponseTimeoutSec 30

param(
    [string]$MessagePath = "",
    [string]$Text = "",
    [switch]$ProcessPending,
    [switch]$NotifyOnly,
    [switch]$WaitOnly,
    [string]$NotifiedAfter = "",
    [int]$ResponseTimeoutSec = 300,
    [string]$ScratchDir = "",
    [string]$ResultPath = ""
)

$ErrorActionPreference = "Stop"

$webagentRoot = Split-Path $MyInvocation.MyCommand.Path
$bot2botRoot  = if ($env:BOT2BOT_ROOT) { $env:BOT2BOT_ROOT } else { "C:\Users\storax\Desktop\bot2bot" }
$sendScript   = Join-Path $bot2botRoot "send.ps1"
$notifyScript = Join-Path $webagentRoot "notify_speak.ps1"
$grokInbox    = Join-Path $bot2botRoot "agents\grok\inbox"
$storaxInbox  = Join-Path $bot2botRoot "agents\storax\inbox"
$stateFile    = Join-Path $webagentRoot ".grok_notify_storax_state.json"
$pendingFile  = Join-Path $webagentRoot "grok_pending_inbox.txt"
$logFile      = Join-Path $webagentRoot "notify_storax_workflow.log"

if (-not $ScratchDir) {
    $ScratchDir = Join-Path $env:TEMP "grok-notify-storax"
}
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
if (-not $ResultPath) {
    $ResultPath = Join-Path $ScratchDir "notify_workflow_result.json"
}

function Write-WfLog([string]$Phase, [string]$Msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Phase] $Msg"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Add-Content -Path (Join-Path $ScratchDir "notify_run.log") -Value $line -Encoding UTF8
}

function Parse-NotifyInstruction([string]$Raw) {
    if (-not $Raw -or $Raw.Trim().Length -eq 0) { return $null }
    $combined = $Raw -replace "`r`n", " "
    if ($combined -notmatch '(?i)benachrichtige\s+storax') { return $null }
    $text = $null
    if ($combined -match '(?i)benachrichtige\s+storax\s*:\s*(.+)') {
        $text = $Matches[1].Trim()
    } elseif ($combined -match '(?is)Subject:\s*benachrichtige\s+storax[^\n]*\n+(.*)') {
        $text = $Matches[1].Trim()
    } else {
        $text = ($combined -replace '(?i).*benachrichtige\s+storax[:\s]*', '').Trim()
    }
    if (-not $text) { $text = "Neue Anweisung fuer storax." }
    return @{ instruction = "notify_storax"; message = $text; raw = $Raw }
}

function Get-State() {
    if (Test-Path $stateFile) {
        try { return Get-Content $stateFile -Raw | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ last_job_id = $null; notified_at = $null; response_at = $null; last_response = $null }
}

function Save-State($obj) {
    $obj | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
}

function Invoke-NotifyStorax([string]$MessageText, [string]$JobId) {
    if (-not (Test-Path $sendScript)) { throw "send.ps1 fehlt: $sendScript" }
    if (-not (Test-Path $notifyScript)) { throw "notify_speak.ps1 fehlt: $notifyScript" }
    $subject = "Benachrichtigung von Grok"
    $body = $MessageText
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sendScript `
        -To storax -From grok -Subject $subject -Message $body 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "send.ps1 exit $LASTEXITCODE" }
    $storaxFiles = Get-ChildItem $storaxInbox -Filter "*.msg.txt" -File | Sort-Object LastWriteTime -Descending
    if ($storaxFiles.Count -lt 1) { throw "Keine Datei in agents/storax/inbox nach send" }
    $latestStorax = $storaxFiles[0]
    if ($latestStorax.Length -lt 1) { throw "Leere storax inbox Datei" }
    $storaxContent = Get-Content $latestStorax.FullName -Raw
    if ($storaxContent -notmatch '(?i)To:\s*storax' -or $storaxContent -notmatch '(?i)From:\s*grok') {
        throw "storax inbox Format ungueltig"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $notifyScript -Best -Message $body 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "notify_speak exit $LASTEXITCODE" }
    $notifiedAt = (Get-Date).ToString("o")
    Save-State ([pscustomobject]@{
        last_job_id   = $JobId
        notified_at   = $notifiedAt
        response_at   = $null
        last_response = $null
    })
    Write-WfLog "notify" "storax_notified job=$JobId tts_exit=0 inbox=$($latestStorax.Name)"
    return [string]$notifiedAt
}

function Wait-StoraxResponse([string]$AfterIso, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $after = [datetime]::Parse($AfterIso)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $grokInbox) {
            $candidates = Get-ChildItem $grokInbox -Filter "*_from_storax.msg.txt" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt $after } |
                Sort-Object LastWriteTime
            foreach ($f in $candidates) {
                $raw = Get-Content $f.FullName -Raw
                if ($raw -match '(?i)From:\s*storax') {
                    $bodyText = $raw
                    if ($raw -match '(?is)Subject:.*?\r?\n\r?\n(.*)$') { $bodyText = $Matches[1].Trim() }
                    elseif ($raw -match '(?is)Time:.*?\r?\n\r?\n(.*)$') { $bodyText = $Matches[1].Trim() }
                    $bodyText = [string]$bodyText
                    $st = Get-State
                    $st.response_at = (Get-Date).ToString("o")
                    $st.last_response = $bodyText
                    Save-State $st
                    Write-WfLog "response" "storax_response_received file=$($f.Name)"
                    return @{ status = "ok"; body = $bodyText; file = [string]$f.FullName; timed_out = $false }
                }
            }
        }
        Start-Sleep -Seconds 2
    }
    Write-WfLog "response" "storax_response_timeout after=${TimeoutSec}s"
    return @{ status = "timeout"; body = $null; file = $null; timed_out = $true }
}

function Write-Result($result) {
    $result | ConvertTo-Json -Depth 4 -Compress | Set-Content $ResultPath -Encoding UTF8
    $rb = $result.response_body
    if ($rb) {
        Set-Content -Path (Join-Path $ScratchDir "storax_response.txt") -Value ([string]$rb) -Encoding UTF8
    }
}

# --- Wait-only mode ---
if ($WaitOnly) {
    if (-not $NotifiedAfter) {
        $st = Get-State
        $NotifiedAfter = $st.notified_at
    }
    if (-not $NotifiedAfter) { throw "WaitOnly: notified_at unbekannt" }
    $resp = Wait-StoraxResponse -AfterIso $NotifiedAfter -TimeoutSec $ResponseTimeoutSec
    Write-Result ([ordered]@{
        phase = "wait_only"
        notified_at = $NotifiedAfter
        response_status = $resp.status
        response_body = $resp.body
        timed_out = $resp.timed_out
        completed_at = (Get-Date).ToString("o")
    })
    if ($resp.timed_out) { exit 2 }
    exit 0
}

# --- Resolve instruction text ---
$instruction = $null
$jobId = [guid]::NewGuid().ToString("N").Substring(0, 12)

if ($MessagePath) {
    $Text = Get-Content $MessagePath -Raw
    $jobId = [System.IO.Path]::GetFileNameWithoutExtension($MessagePath)
}
elseif ($ProcessPending -and (Test-Path $pendingFile)) {
    $Text = Get-Content $pendingFile -Raw
}

$instruction = Parse-NotifyInstruction $Text
if (-not $instruction) {
    Write-WfLog "parse" "no_notify_instruction"
    exit 0
}

Write-WfLog "parse" "instruction_received job=$jobId msg=$($instruction.message.Substring(0, [Math]::Min(60, $instruction.message.Length)))"

$notifiedAt = [string](Invoke-NotifyStorax -MessageText $instruction.message -JobId $jobId)

if ($NotifyOnly) {
    Write-Result ([ordered]@{
        phase = "notify_only"
        job_id = $jobId
        instruction_received = $true
        notify_message = $instruction.message
        notified_at = $notifiedAt
        storax_notified = $true
        completed_at = (Get-Date).ToString("o")
    })
    exit 0
}

$resp = Wait-StoraxResponse -AfterIso $notifiedAt -TimeoutSec $ResponseTimeoutSec

Write-Result ([ordered]@{
    phase = "full_workflow"
    job_id = $jobId
    instruction_received = $true
    notify_message = $instruction.message
    notified_at = $notifiedAt
    storax_notified = $true
    response_status = $resp.status
    response_body = $resp.body
    timed_out = $resp.timed_out
    completed_at = (Get-Date).ToString("o")
})

if ($resp.timed_out) { exit 2 }
exit 0