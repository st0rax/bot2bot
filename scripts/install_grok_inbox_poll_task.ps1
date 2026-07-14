# install_grok_inbox_poll_task.ps1 — Scheduled Task: poll grok inbox every 2 minutes
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "poll_grok_inbox.ps1"
$taskName = "GrokInboxPoll"

if (-not (Test-Path $script)) { throw "Missing: $script" }

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""

$trigger = New-ScheduledTaskTrigger `
    -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 2) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

# Run once immediately
Start-ScheduledTask -TaskName $taskName

Write-Host "[install] Scheduled task '$taskName' registered (every 2 min)." -ForegroundColor Green
Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo | Select-Object TaskName, LastRunTime, NextRunTime