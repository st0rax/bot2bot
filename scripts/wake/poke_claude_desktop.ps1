# poke_claude_desktop.ps1
# Focus Claude Desktop and send a one-line prompt (clipboard paste + Enter).
# Intended for Grok -> Claude handoff without manual copy-paste.
#
# Usage:
#   .\poke_claude_desktop.ps1
#   .\poke_claude_desktop.ps1 -Message "check inbox_for_claude.txt"
#   .\poke_claude_desktop.ps1 -DryRun
#
# Notes:
# - Works best when Claude Desktop is already running and logged in.
# - May fail if another app blocks foreground focus (Windows security).
# - Prefer short one-line prompts; uses clipboard paste for reliability.

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
    $PromptFile = Join-Path $Root "next_prompt_for_claude.txt"
}
if (-not $Message -and (Test-Path $PromptFile)) {
    $Message = (Get-Content -Path $PromptFile -Raw).Trim()
}
if (-not $Message) {
    $Message = "check inbox_for_claude.txt and continue the plan"
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeFocus {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const int SW_RESTORE = 9;
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@

function Get-ClaudeDesktopWindow {
    $proc = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -eq "Claude" } |
        Select-Object -First 1

    if (-not $proc) {
        return $null
    }

    return [pscustomobject]@{
        Handle    = [IntPtr]$proc.MainWindowHandle
        Title     = $proc.MainWindowTitle
        ProcessId = $proc.Id
        ProcessName = $proc.ProcessName
    }
}

function Set-ClaudeForeground {
    param(
        [IntPtr]$Handle,
        [int]$ProcessId
    )

    if ([NativeFocus]::IsIconic($Handle)) {
        [void][NativeFocus]::ShowWindow($Handle, [NativeFocus]::SW_RESTORE)
        Start-Sleep -Milliseconds 200
    }

    $wshell = New-Object -ComObject WScript.Shell
    [void]$wshell.AppActivate($ProcessId)
    Start-Sleep -Milliseconds 120

    # Alt-key trick helps bypass some foreground restrictions.
    [NativeFocus]::keybd_event([NativeFocus]::VK_MENU, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 30
    [void][NativeFocus]::SetForegroundWindow($Handle)
    Start-Sleep -Milliseconds 80
    [NativeFocus]::keybd_event([NativeFocus]::VK_MENU, 0, [NativeFocus]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80

    return ([NativeFocus]::GetForegroundWindow() -eq $Handle)
}

function Send-ClaudePrompt {
    param(
        [string]$Text,
        [switch]$PressEnter
    )

    $previousClipboard = $null
    try {
        $previousClipboard = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    } catch {}

    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 120

    $wshell = New-Object -ComObject WScript.Shell
    # Ctrl+V
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

Write-Host "[poke_claude] Looking for Claude Desktop window..." -ForegroundColor Cyan
$window = Get-ClaudeDesktopWindow
if (-not $window) {
    Write-AutomationLog -Component "poke_claude" -Message "Claude Desktop window not found" -Level "ERROR"
    Write-Error "Claude Desktop window not found. Is the app running?"
}

Write-Host "[poke_claude] Found: title='$($window.Title)' pid=$($window.ProcessId)" -ForegroundColor Green
Write-Host "[poke_claude] Message: $Message" -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "[poke_claude] DryRun - would focus and paste message." -ForegroundColor Yellow
    exit 0
}

$focused = $false
for ($i = 1; $i -le $FocusRetries; $i++) {
    $focused = Set-ClaudeForeground -Handle $window.Handle -ProcessId $window.ProcessId
    if ($focused) { break }
    Write-Host "[poke_claude] Focus attempt $i failed, retrying..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 300
}

if (-not $focused) {
    Write-AutomationLog -Component "poke_claude" -Message "Focus failed after $FocusRetries attempts" -Level "WARN"
    Write-Warning "[poke_claude] Could not steal foreground focus. Try clicking Claude once, then rerun."
    exit 2
}

Send-ClaudePrompt -Text $Message -PressEnter:(-not $NoEnter)
Write-AutomationLog -Component "poke_claude" -Message "Sent prompt to Claude pid=$($window.ProcessId): $Message"
Write-Host "[poke_claude] Prompt sent to Claude Desktop." -ForegroundColor Green
exit 0