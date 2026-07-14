# poll_grok_inbox.ps1
# One-shot inbox poll for agent grok (scheduled task every 2 min).
# Checks bot2bot agents/grok/inbox/*.msg.txt only.
# On new mail: log + Windows toast. Does not mark messages processed (Grok session does that).

$ErrorActionPreference = "Continue"

$bot2botRoot = if ($env:BOT2BOT_ROOT) { $env:BOT2BOT_ROOT } else { (Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) }
$webagentRoot = Join-Path $env:USERPROFILE "Desktop\webagent"
$grokInbox    = Join-Path $bot2botRoot "agents\grok\inbox"
$stateFile    = Join-Path $bot2botRoot ".grok_inbox_poll_state.json"
$logFile      = Join-Path $bot2botRoot "inbox_watch.log"
$pendingFile  = Join-Path $bot2botRoot "grok_pending_inbox.txt"

function Write-Log([string]$Msg) {
    Add-Content -Path $logFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [poll_grok] $Msg" -Encoding UTF8
}

function Get-FileFingerprint([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $item = Get-Item $Path
    $hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    return @{ path = $Path; name = $item.Name; hash = $hash; mtime = $item.LastWriteTimeUtc.Ticks }
}

function Get-InboxFingerprints([string]$Dir) {
    if (-not (Test-Path $Dir)) { return @() }
    Get-ChildItem -Path $Dir -Filter "*.msg.txt" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Get-FileFingerprint $_.FullName }
}

function Show-Toast([string]$Title, [string]$Message) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $text = $template.GetElementsByTagName("text")
        $text.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
        $text.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Grok.InboxPoll").Show($toast)
    } catch {
        Write-Log "Toast fallback: $Title — $Message"
    }
}

if (-not (Test-Path $grokInbox)) {
    New-Item -ItemType Directory -Force -Path $grokInbox | Out-Null
}

$state = @{
    bot2bot = @{}
    last_poll = $null
}
if (Test-Path $stateFile) {
    try {
        $loaded = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($loaded.bot2bot) {
            $loaded.bot2bot.PSObject.Properties | ForEach-Object { $state.bot2bot[$_.Name] = $_.Value }
        }
    } catch { }
}

$newItems = @()
foreach ($fp in Get-InboxFingerprints $grokInbox) {
    $known = $state.bot2bot[$fp.name]
    if ($known -ne $fp.hash) {
        $newItems += $fp
        $state.bot2bot[$fp.name] = $fp.hash
    }
}

$state.last_poll = (Get-Date).ToString("o")
@{ bot2bot = $state.bot2bot; last_poll = $state.last_poll } |
    ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8

if ($newItems.Count -eq 0) { exit 0 }

$lines = @()
foreach ($item in $newItems) {
    $preview = ""
    if (Test-Path $item.path) {
        $preview = (Get-Content $item.path -TotalCount 8 -ErrorAction SilentlyContinue) -join " "
        if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + "..." }
    }
    Write-Log "NEW: $($item.name)"
    if ($preview) { Write-Log $preview }
    $lines += "=== $($item.name) ===`n$(Get-Content $item.path -Raw -ErrorAction SilentlyContinue)"
}

$lines -join "`n`n---`n`n" | Set-Content $pendingFile -Encoding UTF8

$toastMsg = if ($newItems.Count -eq 1) { $newItems[0].name } else { "$($newItems.Count) neue Nachrichten" }
Show-Toast -Title "Grok: neue Inbox-Nachricht" -Message $toastMsg
Write-Log "Notified: $toastMsg"

$handler = Join-Path $webagentRoot "grok_notify_storax.ps1"
foreach ($item in $newItems) {
    if (-not (Test-Path $item.path)) { continue }
    $raw = Get-Content $item.path -Raw -ErrorAction SilentlyContinue
    if ($raw -match '(?i)benachrichtige\s+storax' -and (Test-Path $handler)) {
        Write-Log "Trigger notify_storax workflow: $($item.name)"
        $scratchDir = Join-Path $env:TEMP "grok-notify-storax"
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $handler,
            "-MessagePath", $item.path,
            "-ScratchDir", $scratchDir
        ) | Out-Null
    }
}
exit 0