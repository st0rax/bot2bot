# scripts/wake/window_poke.ps1
# Generalized window poke for Safemode agents (from old poke_*.ps1).
# Focuses a window whose title matches the agent slug (case-insensitive) and
# "types" a notification (or pastes a prompt) so the agent notices new bot2bot inbox.
#
# Usage (as declared in registration.json wake_command):
#   pwsh -NoProfile -File scripts/wake/window_poke.ps1 --agent grok
#   pwsh -NoProfile -File scripts/wake/window_poke.ps1 --agent claude --message "check inbox"
#
# Contract: exit 0 on success (or dry). Non-zero on hard failure.

param(
    [Parameter(Mandatory=$true)][string]$agent,
    [string]$message = "",
    [string]$messageId = "",
    [switch]$dryRun
)

$ErrorActionPreference = "Stop"
$slug = $agent.ToLower()

if (-not $message) {
    $inbox = "agents/$slug/inbox"
    if (Test-Path $inbox) {
        $new = Get-ChildItem $inbox -Filter *.msg* -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First 1
        if ($new) {
            $message = "N new bot2bot messages for $slug (latest: $($new.Name)). Poll inbox."
        }
    }
}
if (-not $message) { $message = "check your bot2bot inbox for new messages ($slug)" }

Write-Host "[wake] agent=$slug msg='$message' dry=$dryRun"

# Simple Windows focus + send text via SendKeys (generalized, no dep on specific poke)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$titleMatch = "*$slug*"
$proc = Get-Process | Where-Object { $_.MainWindowTitle -like $titleMatch -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) {
    # fallback broader
    $proc = Get-Process | Where-Object { $_.MainWindowTitle -match "(?i)$slug|terminal|pwsh|claude|chat" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if ($proc -and $proc.MainWindowHandle) {
    $h = $proc.MainWindowHandle
    [void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
    [Microsoft.VisualBasic.Interaction]::AppActivate($proc.Id) | Out-Null
    Start-Sleep -Milliseconds 200
    if (-not $dryRun) {
        [System.Windows.Forms.SendKeys]::SendWait("`n")  # wake line
        [System.Windows.Forms.SendKeys]::SendWait($message + "{ENTER}")
    }
    Write-Host "[wake] poked window for $slug (handle=$h)"
    exit 0
} else {
    Write-Host "[wake] no matching window for $slug; message would be: $message"
    if ($dryRun) { exit 0 }
    # still success if no window (agent may poll anyway)
    exit 0
}
