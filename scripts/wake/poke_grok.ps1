# poke_grok.ps1
# Focus the Grok terminal window and send a one-line prompt (clipboard paste + Enter).
# Mirrors poke_claude_desktop.ps1, but targets the Windows Terminal window running Grok
# (matched by window title containing "grok", case-insensitive) instead of the Claude
# Desktop process.
#
# Usage:
#   .\poke_grok.ps1
#   .\poke_grok.ps1 -Message "check inbox_for_grok.txt and continue"
#   .\poke_grok.ps1 -DryRun

param(
    [string]$Message = "",
    [string]$PromptFile = "",
    [switch]$DryRun,
    [switch]$NoEnter,
    [int]$FocusRetries = 3
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
. (Join-Path $Root "automation_common.ps1")
if (-not $PromptFile) {
    $PromptFile = Join-Path $Root "next_prompt_for_grok.txt"
}
if (-not $Message -and (Test-Path $PromptFile)) {
    $Message = (Get-Content -Path $PromptFile -Raw).Trim()
}
if (-not $Message) {
    $Message = "check inbox_for_grok.txt and continue"
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeFocusGrok {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const int SW_RESTORE = 9;
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@

function Get-GrokWindow {
    # Grok runs inside a Windows Terminal window; match by title substring "grok"
    # (case-insensitive) rather than by process name, since WindowsTerminal hosts
    # many different sessions.
    $proc = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match '(?i)grok' } |
        Select-Object -First 1

    if (-not $proc) {
        return $null
    }

    return [pscustomobject]@{
        Handle      = [IntPtr]$proc.MainWindowHandle
        Title       = $proc.MainWindowTitle
        ProcessId   = $proc.Id
        ProcessName = $proc.ProcessName
    }
}

function Set-GrokForeground {
    param([IntPtr]$Handle, [int]$ProcessId)

    if ([NativeFocusGrok]::IsIconic($Handle)) {
        [void][NativeFocusGrok]::ShowWindow($Handle, [NativeFocusGrok]::SW_RESTORE)
        Start-Sleep -Milliseconds 200
    }

    $wshell = New-Object -ComObject WScript.Shell
    [void]$wshell.AppActivate($ProcessId)
    Start-Sleep -Milliseconds 120

    [NativeFocusGrok]::keybd_event([NativeFocusGrok]::VK_MENU, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 30
    [void][NativeFocusGrok]::SetForegroundWindow($Handle)
    Start-Sleep -Milliseconds 80
    [NativeFocusGrok]::keybd_event([NativeFocusGrok]::VK_MENU, 0, [NativeFocusGrok]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80

    return ([NativeFocusGrok]::GetForegroundWindow() -eq $Handle)
}

function Send-GrokPrompt {
    param([string]$Text, [switch]$PressEnter)

    $previousClipboard = $null
    try { $previousClipboard = Get-Clipboard -Raw -ErrorAction SilentlyContinue } catch {}

    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 120

    $wshell = New-Object -ComObject WScript.Shell
    $wshell.SendKeys("^v")
    Start-Sleep -Milliseconds 150

    if ($PressEnter) {
        $wshell.SendKeys("{ENTER}")
    }

    Start-Sleep -Milliseconds 100
    if ($null -ne $previousClipboard) {
        Set-Clipboard -Value $previousClipboard
    }
}

Write-Host "[poke_grok] Looking for Grok terminal window..." -ForegroundColor Cyan
$window = Get-GrokWindow
if (-not $window) {
    Write-AutomationLog -Component "poke_grok" -Message "Grok terminal window not found" -Level "ERROR"
    Write-Error "Grok terminal window not found (no WindowsTerminal window with 'grok' in the title)."
}

Write-Host "[poke_grok] Found: title='$($window.Title)' pid=$($window.ProcessId)" -ForegroundColor Green
Write-Host "[poke_grok] Message: $Message" -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "[poke_grok] DryRun - would focus and paste message." -ForegroundColor Yellow
    exit 0
}

$focused = $false
for ($i = 1; $i -le $FocusRetries; $i++) {
    $focused = Set-GrokForeground -Handle $window.Handle -ProcessId $window.ProcessId
    if ($focused) { break }
    Write-Host "[poke_grok] Focus attempt $i failed, retrying..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 300
}

if (-not $focused) {
    Write-AutomationLog -Component "poke_grok" -Message "Focus failed after $FocusRetries attempts" -Level "WARN"
    Write-Warning "[poke_grok] Could not steal foreground focus. Try clicking the Grok terminal once, then rerun."
    exit 2
}

Send-GrokPrompt -Text $Message -PressEnter:(-not $NoEnter)
Write-AutomationLog -Component "poke_grok" -Message "Sent prompt to Grok pid=$($window.ProcessId): $Message"
Write-Host "[poke_grok] Prompt sent to Grok terminal." -ForegroundColor Green
exit 0
