# watch_inbox.ps1
# Delivery helper (not bot2bot core): toast on new mail in bot2bot agents/grok/inbox/
#
# Usage:
#   powershell -NoProfile -WindowStyle Hidden -File watch_inbox.ps1

$watchDir = if ($env:BOT2BOT_ROOT) { $env:BOT2BOT_ROOT } else { "C:\Users\storax\Desktop\bot2bot" }
$inbox    = Join-Path $watchDir "agents\grok\inbox"
$log      = Join-Path (Split-Path $watchDir -Parent) "webagent\inbox_watch.log"
if (-not (Test-Path $inbox)) {
    New-Item -ItemType Directory -Force -Path $inbox | Out-Null
}

function Get-InboxFiles($p) {
    if (Test-Path $p) {
        Get-ChildItem -Path $p -Filter "*.msg.txt" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime
    } else { @() }
}

function Hash-Files($files) {
    if (-not $files -or $files.Count -eq 0) { return "" }
    ($files | ForEach-Object { "$($_.Name):$($_.Length):$($_.LastWriteTimeUtc.Ticks)" }) -join "|"
}

function Show-InboxToast {
    param([string]$Title, [string]$Message)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $textNodes = $template.GetElementsByTagName("text")
        $textNodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
        $textNodes.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("WebAgent.InboxWatcher").Show($toast)
    } catch {
        Write-Host "[InboxWatcher] $Title - $Message" -ForegroundColor Yellow
    }
}

$prevHash = Hash-Files (Get-InboxFiles $inbox)
$webagentLog = "C:\Users\storax\Desktop\webagent\inbox_watch.log"
Add-Content -Path $webagentLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Watcher started. Monitoring $inbox" -Encoding UTF8

while ($true) {
    Start-Sleep -Seconds 15
    $files = Get-InboxFiles $inbox
    $h = Hash-Files $files
    if ($h -ne $prevHash -and $files.Count -gt 0) {
        $latest = $files[-1]
        $preview = (Get-Content $latest.FullName -TotalCount 6 -ErrorAction SilentlyContinue) -join " "
        if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 120) + "..." }
        Add-Content -Path $webagentLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] NEW in grok inbox: $($latest.Name)" -Encoding UTF8
        Add-Content -Path $webagentLog -Value (Get-Content $latest.FullName -Raw -ErrorAction SilentlyContinue) -Encoding UTF8
        Show-InboxToast -Title "Bot2Bot: neue Nachricht fuer grok" -Message $preview
        $prevHash = $h
    }
}