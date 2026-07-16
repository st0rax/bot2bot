# poke.ps1 — shortcut for agents (e.g. vibe) to notify another agent.
# Usage:
#   .\poke.ps1 -To grok
#   .\poke.ps1 -To grok -Message "check inbox and continue"
#   .\poke.ps1 -To grok -Async   # required when caller runs inside the same Windows Terminal

param(
    [Parameter(Mandatory)]
    [string]$To,

    [string]$Message = "",
    [switch]$Async
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
$toSlug = $To.ToLower()

if ($Async) {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $pokeScript, "-AgentName", $toSlug)
    if ($Message) { $args += @("-Message", $Message) }
    Start-Process -FilePath "pwsh" -ArgumentList $args -WorkingDirectory $PSScriptRoot -WindowStyle Hidden | Out-Null
    Write-Host "[poke] Async poke queued for $toSlug (detached pwsh)." -ForegroundColor Green
    Write-Bot2BotLog -Component "poke" -Message "Async poke queued for $toSlug"
    exit 0
}

& $pokeScript -AgentName $toSlug -Message $Message
exit $LASTEXITCODE