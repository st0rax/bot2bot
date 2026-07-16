# append_message.ps1
# Append one message to history/conversation.jsonl and update the recipient inbox.
#
# Usage:
#   .\append_message.ps1 -From grok -To claude -Subject "Hello" -Body "Please review X" -Status info
#   .\append_message.ps1 -From claude -To grok -Subject "Approved" -Body "LGTM" -Status approved -InReplyTo <uuid>
#   .\append_message.ps1 ... -Poke   # also focus recipient and send poke_template

param(
    [Parameter(Mandatory)]
    [string]$From,

    [Parameter(Mandatory)]
    [string]$To,

    [Parameter(Mandatory)]
    [string]$Subject,

    [string]$Body = "",

    [string]$BodyPath = "",

    [ValidateSet("info", "proposed", "approved", "rejected", "question")]
    [string]$Status = "info",

    [string]$InReplyTo = "",
    [string[]]$Refs = @(),
    [switch]$Poke,
    [switch]$PokeHeaded,
    [switch]$HumanAttention,
    [switch]$NoInboxUpdate,
    [switch]$NoMediatorReport
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

if ($BodyPath) {
    if (-not (Test-Path -LiteralPath $BodyPath)) {
        throw "BodyPath not found: $BodyPath"
    }
    $Body = Get-Content -LiteralPath $BodyPath -Raw -Encoding UTF8
}
if (-not $Body) {
    throw "Either -Body or -BodyPath is required"
}

$root = Get-Bot2BotRoot
$fromSlug = $From.ToLower()
$toSlug = $To.ToLower()

if ($fromSlug -notmatch '^[a-z][a-z0-9_-]{0,31}$') {
    throw "Invalid sender agent id: $From"
}
if ($toSlug -ne "broadcast" -and $toSlug -notmatch '^[a-z][a-z0-9_-]{0,31}$') {
    throw "Invalid recipient agent id: $To"
}

$historyPath = Get-HistoryPath -Root $root
$historyDir = Split-Path $historyPath -Parent
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}
if (-not (Test-Path $historyPath)) {
    New-Item -ItemType File -Path $historyPath -Force | Out-Null
}

$message = [ordered]@{
    id          = New-Bot2BotMessageId
    ts          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    from        = $fromSlug
    to          = $toSlug
    in_reply_to = if ($InReplyTo) { $InReplyTo } else { $null }
    subject     = $Subject
    status      = $Status
    body        = $Body
    refs        = @($Refs)
}

$jsonLine = ($message | ConvertTo-Json -Compress -Depth 5)
Add-Content -Path $historyPath -Value $jsonLine -Encoding UTF8 -NoNewline:$false
Write-Bot2BotLog -Component "append_message" -Message "Appended id=$($message.id) from=$fromSlug to=$toSlug"

if (-not $NoInboxUpdate -and $toSlug -ne "broadcast") {
    $inboxPath = Get-InboxPath -AgentName $toSlug -Root $root
    $pointer = Format-InboxPointer -Message ([pscustomobject]$message) -Root $root
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($inboxPath, $pointer, $utf8NoBom)
    Write-Bot2BotLog -Component "append_message" -Message "Updated inbox for $toSlug"
}

Write-Host "[append_message] OK id=$($message.id)" -ForegroundColor Green
Write-Host "  history: $historyPath" -ForegroundColor DarkGray
if (-not $NoInboxUpdate -and $toSlug -ne "broadcast") {
    Write-Host "  inbox:   $(Get-InboxPath -AgentName $toSlug -Root $root)" -ForegroundColor DarkGray
}

$needsHumanLog = $HumanAttention -or (Test-MessageNeedsHumanAttention -Subject $Subject -Body $Body -Status $Status)
if ($needsHumanLog -and -not $HumanAttention) {
    Write-Bot2BotLog -Component "append_message" -Message "Human attention noted for $toSlug (no audio  Storax-only policy)" -Level "INFO"
}
if (Test-ShouldPlayStoraxAudio -To $toSlug -HumanAttention:$HumanAttention) {
    $spoken = Format-StoraxSpokenMessage -Subject $Subject -Body $Body -Status $Status
    Invoke-HumanAttentionAudio -Message $spoken
}

if ($Poke -and $toSlug -ne "broadcast") {
    if (-not (Test-AgentIsActive -AgentName $toSlug -Root $root)) {
        $cfg = Get-AgentConfig -AgentName $toSlug -Root $root
        $reason = if ($cfg.InactiveReason) { " ($($cfg.InactiveReason))" } else { "" }
        Write-Host "[append_message] Recipient $toSlug is INACTIVE$reason - poke skipped." -ForegroundColor Yellow
        Write-Bot2BotLog -Component "append_message" -Message "Poke skipped for inactive $toSlug$reason" -Level "WARN"
        Write-Bot2BotLog -Component "append_message" -Message "Inactive agent $toSlug  poke skipped (no audio)" -Level "WARN"
    } else {
        $pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
        $pokeArgs = @{ AgentName = $toSlug }
        if ($PokeHeaded) { $pokeArgs.Headed = $true }
        $useAsyncPoke = $false
        try {
            $fromConfig = Get-AgentConfig -AgentName $fromSlug -Root $root
            $useAsyncPoke = ($fromConfig.Kind -eq "console")
        } catch {}
        if ($useAsyncPoke) {
            $spawnArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $pokeScript, "-AgentName", $toSlug)
            if ($PokeHeaded) { $spawnArgs += "-Headed" }
            Start-Process -FilePath "pwsh" -ArgumentList $spawnArgs -WorkingDirectory $PSScriptRoot -WindowStyle Hidden | Out-Null
            Write-Host "[append_message] Async poke queued for $toSlug (console sender $fromSlug)." -ForegroundColor DarkGray
            Write-Bot2BotLog -Component "append_message" -Message "Async poke queued for $toSlug from $fromSlug"
        } else {
            & $pokeScript @pokeArgs
        }
        if (-not $useAsyncPoke -and $LASTEXITCODE -ne 0) {
            Write-Bot2BotLog -Component "append_message" -Message "Poke failed for $toSlug (no audio  Storax-only policy)" -Level "WARN"
            exit $LASTEXITCODE
        }
    }
}

if (-not $NoMediatorReport -and $fromSlug -ne "chatgpt") {
    $reportScript = Join-Path $PSScriptRoot "report_mediator_event.ps1"
    if (Test-Path $reportScript) {
        try {
            & $reportScript -Agent $fromSlug -Event write -MsgId $message.id -Peer $toSlug `
                -Subject $Subject -Status $Status -NoLedger:$false | Out-Null
        } catch {
            Write-Bot2BotLog -Component "append_message" -Message "Mediator report failed: $_" -Level "WARN"
        }
    }
}

Write-Output ([pscustomobject]$message)


