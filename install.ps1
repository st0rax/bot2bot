# install.ps1 — Lokaler Installer (Entwicklungsbaum -> Desktop-Ziel)
#
#   .\install.ps1
#   .\install.ps1 -NonInteractive -TargetWebagent C:\Test\webagent

param(
    [string]$TargetWebagent = "",
    [string]$TargetBot2bot = "",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktop = [Environment]::GetFolderPath("Desktop")
if (-not $TargetWebagent) { $TargetWebagent = Join-Path $desktop "webagent" }
if (-not $TargetBot2bot) { $TargetBot2bot = Join-Path $desktop "bot2bot" }

$args = @{
    TargetDir = $TargetWebagent
    Bot2BotDir = $TargetBot2bot
    SourceWebagent = Join-Path (Split-Path $here -Parent) "webagent"
}
if ($NonInteractive) { $args.NonInteractive = $true }

& (Join-Path $here "scripts\install_webagent.ps1") @args