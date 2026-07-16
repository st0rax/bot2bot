# record_storax_intervention.ps1
# Records a Storax intervention, opens penalty vote for grok+vibe (amounts unanimous).
# Storax receives bonus only after unanimous vote; no automatic malus for Storax.
#
# Usage:
#   .\record_storax_intervention.ps1 -Summary "Deadlock: beide warteten" -Context "inbox/grok.txt E FERTIG ungeprueft"

param(
    [Parameter(Mandatory)]
    [string]$Summary,

    [string]$Context = "",
    [string[]]$Involved = @("grok", "vibe"),
    [string]$IndexPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$indexPath = if ($IndexPath) { $IndexPath } else { Join-Path $root "data\leistungsindex.json" }
if (-not (Test-Path $indexPath)) { throw "Leistungsindex not found: $indexPath" }

$idx = Get-Content $indexPath -Raw | ConvertFrom-Json
$interventionCount = @($idx.events | Where-Object { $_.kind -eq "intervention" }).Count
$caseId = "INT-{0:000}" -f ($interventionCount + 1)
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$defaults = $idx.policy.defaults
$proposedBonus = [int]$defaults.storax_bonus
$proposedVibeMalus = [int]$defaults.agent_malus_vibe
$proposedGrokMalus = $proposedVibeMalus * [int]$defaults.grok_multiplier

$idx.participants.storax.intervention_count += 1

$event = [ordered]@{
    id       = $caseId
    ts       = $ts
    kind     = "intervention"
    agent    = "storax"
    delta    = 0
    reason   = $Summary
    context  = $Context
    involved = @($Involved)
    note     = "Storax-Bonus und Agent-Malus erst nach einstimmiger Hoehen-Abstimmung (grok+vibe)"
}
$idx.events += [pscustomobject]$event

$case = [ordered]@{
    case_id          = $caseId
    opened_at        = $ts
    summary          = $Summary
    context          = $Context
    involved         = @($Involved)
    voters           = @($idx.policy.voters)
    votes            = [ordered]@{}
    proposed_bonus   = $proposedBonus
    proposed_vibe    = $proposedVibeMalus
    proposed_grok    = $proposedGrokMalus
    grok_multiplier  = [int]$defaults.grok_multiplier
    verdict          = $null
    status           = "pending_penalty_vote"
}
$idx.open_cases += [pscustomobject]$case
$idx | ConvertTo-Json -Depth 12 | Set-Content -Path $indexPath -Encoding UTF8

Write-Bot2BotLog -Component "leistungsindex" -Message "Intervention $caseId recorded; pending vote storax +$proposedBonus vibe $proposedVibeMalus grok $proposedGrokMalus"
Write-Host "[leistungsindex] $caseId opened - pending vote: storax +$proposedBonus, vibe $proposedVibeMalus, grok $proposedGrokMalus (2x)" -ForegroundColor Yellow
Write-Host "  Abstimmung: grok + vibe einstimmig via vote_penalty.ps1 (Storax stimmt nicht mit)." -ForegroundColor DarkGray
Write-Output ([pscustomobject]@{ case_id = $caseId; proposed = @{ storax = $proposedBonus; vibe = $proposedVibeMalus; grok = $proposedGrokMalus } })