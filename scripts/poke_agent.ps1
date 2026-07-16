# poke_agent.ps1
# Agent-agnostic poke: desktop window focus OR webbrain bridge dispatch.
#
# Usage:
#   .\poke_agent.ps1 -AgentName claude
#   .\poke_agent.ps1 -AgentName grok -Message "check inbox/grok.txt"
#   .\poke_agent.ps1 -AgentName kimi -ProcessName "WindowsTerminal" -WindowTitlePattern "kimi" -DryRun

param(
    [Parameter(Mandatory)]
    [string]$AgentName,

    [string]$Message = "",
    [string]$ProcessName = "",
    [string]$WindowTitlePattern = "",
    [switch]$DryRun,
    [switch]$Headed,
    [switch]$NoEnter,
    [int]$FocusRetries = 3
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$config = Get-AgentConfig -AgentName $AgentName -Root $root

if (-not $config.Active) {
    $reason = if ($config.InactiveReason) { " ($($config.InactiveReason))" } else { "" }
    Write-Host "`[poke_agent`] Agent $($config.Name) is INACTIVE$reason - skipping poke." -ForegroundColor Yellow
    Write-Bot2BotLog -Component "poke_agent" -Message "Skipped inactive agent $($config.Name)$reason" -Level "WARN"
    exit 0
}

if ($config.Kind -eq "webbrain") {
    $bridgeScript = Join-Path $PSScriptRoot "bot2bot_webbrain_bridge.ps1"
    if (-not (Test-Path $bridgeScript)) {
        Write-Error "Webbrain bridge not installed: $bridgeScript (apply PROPOSED_DIFF_016)."
    }
    Write-Host "`[poke_agent`] Webbrain: $($config.Name) brain_id=$($config.BrainId)" -ForegroundColor Cyan
    $bridgeArgs = @{ AgentName = $config.Name; Root = $root }
    if ($DryRun) { $bridgeArgs.DryRun = $true }
    if ($Headed) { $bridgeArgs.Headed = $true }
    & $bridgeScript @bridgeArgs
    exit $LASTEXITCODE
}

if ($ProcessName) { $config.ProcessName = $ProcessName }
if ($WindowTitlePattern) { $config.WindowTitlePattern = $WindowTitlePattern }

if (-not $Message) {
    $inboxPath = Get-InboxPath -AgentName $config.Name -Root $root
    $template = $config.PokeTemplate
    if (-not $template) {
        $template = "check {inbox_path} and continue"
    }
    $Message = $template.Replace("{inbox_path}", $inboxPath)
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class B2BNativeFocus {
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

function Get-WindowsTerminalShell {
    $proc = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
    if (-not $proc) { return $null }
    return [pscustomobject]@{
        Handle      = [IntPtr]$proc.MainWindowHandle
        Title       = $proc.MainWindowTitle
        ProcessId   = $proc.Id
        ProcessName = $proc.ProcessName
    }
}

function Get-AgentWindow {
    param(
        [string]$ProcessName,
        [string]$TitlePattern
    )
    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match $TitlePattern }

    $proc = $procs | Select-Object -First 1
    if (-not $proc) { return $null }

    return [pscustomobject]@{
        Handle      = [IntPtr]$proc.MainWindowHandle
        Title       = $proc.MainWindowTitle
        ProcessId   = $proc.Id
        ProcessName = $proc.ProcessName
    }
}

function Select-WindowsTerminalTabByIndex {
    param(
        [int]$ProcessId,
        [int]$TabIndex,
        [string]$TitlePattern = ""
    )
    if ($TabIndex -lt 1 -or $TabIndex -gt 9) {
        Write-Host "`[poke_agent`] tab_index must be 1-9 (got $TabIndex)" -ForegroundColor Yellow
        return $false
    }

    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }

    # tab_index is authoritative — do not skip switch when title regex matches:
    # multiple WT tabs can share the same suffix (e.g. "... - grok").
    $wshell = New-Object -ComObject WScript.Shell
    Write-Host "`[poke_agent`] Jumping to tab $TabIndex (Ctrl+Alt+$TabIndex)..." -ForegroundColor DarkGray
    $wshell.SendKeys("^%{$TabIndex}")
    Start-Sleep -Milliseconds 450
    $proc.Refresh()

    if ($TitlePattern -and $proc.MainWindowTitle -notmatch $TitlePattern) {
        Write-Host "`[poke_agent`] Tab $TabIndex title mismatch (now: '$($proc.MainWindowTitle)', expected: '$TitlePattern')" -ForegroundColor Yellow
        return $false
    }
    Write-Host "`[poke_agent`] Tab $TabIndex selected: '$($proc.MainWindowTitle)'" -ForegroundColor Green
    return $true
}

function Select-WindowsTerminalTab {
    param(
        [int]$ProcessId,
        [string]$TitlePattern
    )
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }

    $proc.Refresh()
    if ($proc.MainWindowTitle -match $TitlePattern) {
        Write-Host "`[poke_agent`] Already on target tab: '$($proc.MainWindowTitle)'" -ForegroundColor Green
        return $true
    }

    # Two-tab setup (grok / vibe): one Ctrl+Tab reaches the only other tab.
    $wshell = New-Object -ComObject WScript.Shell
    Write-Host "`[poke_agent`] Switching once to the other tab (Ctrl+Tab)..." -ForegroundColor DarkGray
    $wshell.SendKeys("^{TAB}")
    Start-Sleep -Milliseconds 450
    $proc.Refresh()
    if ($proc.MainWindowTitle -match $TitlePattern) {
        Write-Host "`[poke_agent`] Tab selected: '$($proc.MainWindowTitle)'" -ForegroundColor Green
        return $true
    }

    Write-Host "`[poke_agent`] Other tab did not match '$TitlePattern' (now: '$($proc.MainWindowTitle)')" -ForegroundColor Yellow
    return $false
}

function Set-AgentForeground {
    param([IntPtr]$Handle, [int]$ProcessId)

    if ([B2BNativeFocus]::IsIconic($Handle)) {
        [void][B2BNativeFocus]::ShowWindow($Handle, [B2BNativeFocus]::SW_RESTORE)
        Start-Sleep -Milliseconds 200
    }

    $wshell = New-Object -ComObject WScript.Shell
    [void]$wshell.AppActivate($ProcessId)
    Start-Sleep -Milliseconds 120

    [B2BNativeFocus]::keybd_event([B2BNativeFocus]::VK_MENU, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 30
    [void][B2BNativeFocus]::SetForegroundWindow($Handle)
    Start-Sleep -Milliseconds 80
    [B2BNativeFocus]::keybd_event([B2BNativeFocus]::VK_MENU, 0, [B2BNativeFocus]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80

    return ([B2BNativeFocus]::GetForegroundWindow() -eq $Handle)
}

function Send-AgentPrompt {
    param([string]$Text, [switch]$PressEnter)

    $previousClipboard = $null
    try { $previousClipboard = Get-Clipboard -Raw -ErrorAction SilentlyContinue } catch {}

    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 120

    $wshell = New-Object -ComObject WScript.Shell
    $wshell.SendKeys("^v")
    Start-Sleep -Milliseconds 150
    if ($PressEnter) { $wshell.SendKeys("{ENTER}") }
    Start-Sleep -Milliseconds 100

    if ($null -ne $previousClipboard) {
        Set-Clipboard -Value $previousClipboard
    }
}

Write-Host "`[poke_agent`] Agent: $($config.Name) ($($config.DisplayName))" -ForegroundColor Cyan
Write-Host "`[poke_agent`] Looking for process '$($config.ProcessName)' title '$($config.WindowTitlePattern)'..." -ForegroundColor DarkGray

$window = $null
$useTabSelect = $false
$tabPattern = $config.WindowTitlePattern

if ($config.ProcessName -eq "WindowsTerminal" -and ($config.TabIndex -ge 1 -or $tabPattern)) {
    $window = Get-WindowsTerminalShell
    if ($window) {
        $useTabSelect = $true
        if ($config.TabIndex -ge 1) {
            Write-Host "`[poke_agent`] WindowsTerminal shell pid=$($window.ProcessId), tab_index=$($config.TabIndex)..." -ForegroundColor DarkGray
        } else {
            Write-Host "`[poke_agent`] WindowsTerminal shell pid=$($window.ProcessId), title '$tabPattern'..." -ForegroundColor DarkGray
        }
    }
}
if (-not $window -and $config.ProcessName -and $config.WindowTitlePattern) {
    $window = Get-AgentWindow -ProcessName $config.ProcessName -TitlePattern $config.WindowTitlePattern
}
if (-not $window -and $config.FallbackProcessName -eq "WindowsTerminal" -and $config.FallbackWindowTitlePattern) {
    $window = Get-WindowsTerminalShell
    if ($window) {
        $useTabSelect = $true
        $tabPattern = $config.FallbackWindowTitlePattern
        Write-Host "`[poke_agent`] Fallback WindowsTerminal shell, tab '$tabPattern'..." -ForegroundColor DarkGray
    }
} elseif (-not $window -and $config.FallbackProcessName -and $config.FallbackWindowTitlePattern) {
    Write-Host "`[poke_agent`] Fallback: '$($config.FallbackProcessName)' title '$($config.FallbackWindowTitlePattern)'..." -ForegroundColor DarkGray
    $window = Get-AgentWindow -ProcessName $config.FallbackProcessName -TitlePattern $config.FallbackWindowTitlePattern
}
if (-not $window -and ($config.Kind -eq "console" -or $config.PokeFallback -eq "audio")) {
    if ($DryRun) {
        Write-Host "`[poke_agent`] DryRun - no focusable window (console agent)." -ForegroundColor Yellow
        exit 0
    }
    Write-Bot2BotLog -Component "poke_agent" -Message "Console poke failed for $($config.Name) - no window/tab (no audio, Storax-only policy)" -Level "WARN"
    Write-Host "`[poke_agent`] No focusable window for console agent '$($config.Name)'." -ForegroundColor Yellow
    exit 1
}
if (-not $window) {
    Write-Bot2BotLog -Component "poke_agent" -Message "Window not found for agent $($config.Name)" -Level "ERROR"
    Write-Error "No window found for agent '$($config.Name)'. Is the app running? Adjust agents/registry.json or pass -ProcessName / -WindowTitlePattern."
}

Write-Host "`[poke_agent`] Found: '$($window.Title)' pid=$($window.ProcessId)" -ForegroundColor Green
Write-Host "`[poke_agent`] Message: $Message" -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "`[poke_agent`] DryRun - would focus and paste." -ForegroundColor Yellow
    exit 0
}

$focused = $false
for ($i = 1; $i -le $FocusRetries; $i++) {
    $focused = Set-AgentForeground -Handle $window.Handle -ProcessId $window.ProcessId
    if ($focused) { break }
    Write-Host "`[poke_agent`] Focus attempt $i failed..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 300
}

if (-not $focused) {
    Write-Bot2BotLog -Component "poke_agent" -Message "Focus failed for $($config.Name)" -Level "WARN"
    Write-Warning "`[poke_agent`] Could not steal focus. Click the agent window once, then rerun."
    exit 2
}

if ($useTabSelect) {
    $tabOk = $false
    if ($config.TabIndex -ge 1) {
        $tabOk = Select-WindowsTerminalTabByIndex -ProcessId $window.ProcessId -TabIndex $config.TabIndex -TitlePattern $tabPattern
        # tab_index stale (e.g. all tabs renamed to grok): try title-based hop
        if (-not $tabOk -and $tabPattern) {
            Write-Host "`[poke_agent`] tab_index miss — fallback title search '$tabPattern'..." -ForegroundColor Yellow
            $tabOk = Select-WindowsTerminalTab -ProcessId $window.ProcessId -TitlePattern $tabPattern
        }
        if (-not $tabOk -and $tabPattern) {
            $proc = Get-Process -Id $window.ProcessId -ErrorAction SilentlyContinue
            $wshell = New-Object -ComObject WScript.Shell
            for ($t = 1; $t -le 8; $t++) {
                $wshell.SendKeys("^{TAB}")
                Start-Sleep -Milliseconds 400
                $proc.Refresh()
                if ($proc.MainWindowTitle -match $tabPattern) {
                    Write-Host "`[poke_agent`] Found via Ctrl+Tab cycle: '$($proc.MainWindowTitle)'" -ForegroundColor Green
                    $tabOk = $true
                    break
                }
            }
        }
    } elseif ($tabPattern) {
        $tabOk = Select-WindowsTerminalTab -ProcessId $window.ProcessId -TitlePattern $tabPattern
    }
    if (-not $tabOk) {
        Write-Bot2BotLog -Component "poke_agent" -Message "Tab select failed for $($config.Name) (no audio, Storax-only policy)" -Level "WARN"
        if ($config.TabIndex -ge 1) {
            Write-Error "Windows Terminal tab $($config.TabIndex) not reachable for '$($config.Name)'."
        } else {
            Write-Error "Windows Terminal tab matching '$tabPattern' not found."
        }
    }
}

Send-AgentPrompt -Text $Message -PressEnter:(-not $NoEnter)
Write-Bot2BotLog -Component "poke_agent" -Message "Poked $($config.Name) pid=$($window.ProcessId)"
Write-Host "`[poke_agent`] Prompt sent." -ForegroundColor Green
exit 0