# ankh_on_demand.ps1 — Revival briefing erzeugen (+ optional poke)
#
#   .\ankh_on_demand.ps1
#   .\ankh_on_demand.ps1 -AgentName vibe -Poke
#   .\ankh_on_demand.ps1 -Quiet

param(
    [string]$AgentName = "claude",
    [switch]$Poke,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")
$ankhScript = Join-Path $PSScriptRoot "ankh.ps1"
if (-not (Test-Path $ankhScript)) { throw "ankh.ps1 not found: $ankhScript" }

$ankhArgs = @{ AgentName = $AgentName }
if ($Quiet) { $ankhArgs.Quiet = $true }

& $ankhScript @ankhArgs

if ($Poke) {
    $pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
    & $pokeScript -AgentName $AgentName
}

Write-Bot2BotLog -Component "ankh_on_demand" -Message "Revival briefing for $AgentName (poke=$($Poke.IsPresent))"