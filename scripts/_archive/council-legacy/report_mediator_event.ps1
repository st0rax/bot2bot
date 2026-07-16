# report_mediator_event.ps1
# Report inbox read/write/status events to the ChatGPT mediator ledger.
#
# Usage:
#   .\report_mediator_event.ps1 -Agent grok -Event read -MsgId ca622995
#   .\report_mediator_event.ps1 -Agent grok -Event write -MsgId new-id -Peer vibe -Subject "..." -Status info

param(
    [Parameter(Mandatory)]
    [string]$Agent,

    [Parameter(Mandatory)]
    [ValidateSet("read", "write", "status")]
    [string]$Event,

    [string]$MsgId = "",
    [string]$Peer = "",
    [string]$Subject = "",
    [string]$Status = "",
    [string]$Notes = "",
    [switch]$NotifyChatGpt,
    [switch]$NoLedger
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$mediatorDir = Join-Path $root "data\mediator"
if (-not (Test-Path $mediatorDir)) { New-Item -ItemType Directory -Path $mediatorDir -Force | Out-Null }
$ledgerPath = Join-Path $mediatorDir "events.jsonl"

$entry = [ordered]@{
    id      = (New-Bot2BotMessageId)
    ts      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    agent   = $Agent.ToLower()
    event   = $Event
    msg_id  = $MsgId
    peer    = $Peer.ToLower()
    subject = $Subject
    status  = $Status
    notes   = $Notes
}

if (-not $NoLedger) {
    ($entry | ConvertTo-Json -Compress -Depth 4) | Add-Content -Path $ledgerPath -Encoding UTF8
}

Write-Bot2BotLog -Component "mediator" -Message "$($entry.agent) $Event msg=$MsgId peer=$Peer"

if ($NotifyChatGpt) {
    $appendScript = Join-Path $PSScriptRoot "append_message.ps1"
    $body = @(
        "MEDIATOR-EVENT: $($entry.event)"
        "agent=$($entry.agent) msg_id=$($entry.msg_id) peer=$($entry.peer)"
        "subject=$($entry.subject) status=$($entry.status)"
        if ($Notes) { "notes=$Notes" }
    ) -join "`n"
    & $appendScript -From $entry.agent -To chatgpt -Subject "[$($entry.event)] $($entry.agent) -> $($entry.peer)" -Body $body -Status info -NoMediatorReport | Out-Null
}

Write-Output ([pscustomobject]$entry)