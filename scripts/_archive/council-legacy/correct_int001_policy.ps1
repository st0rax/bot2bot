# correct_int001_policy.ps1
# One-time retroactive correction for INT-001 under revised Storax policy (schema v2).

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$indexPath = Join-Path $root "data\leistungsindex.json"
$idx = Get-Content $indexPath -Raw | ConvertFrom-Json

# Approved amounts (grok proposal; vibe confirmation pending via inbox)
$storaxBonus = 5
$vibeMalus = -4
$grokMalus = -8
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Reverse old wrongful storax -5
$idx.participants.storax.score = 0
$idx.participants.storax.intervention_count = 1

# Reverse old grok-only fault -8; apply new split
$idx.participants.grok.score = $grokMalus
$idx.participants.grok.fault_count = 1
$idx.participants.vibe.score = $vibeMalus
$idx.participants.vibe.fault_count = 1

# Apply storax bonus
$idx.participants.storax.score += $storaxBonus

# Rebuild events: fix INT-001 intervention, drop old fault_verdict, add correction entries
$keptEvents = @($idx.events | Where-Object { $_.id -notin @("INT-001", "INT-001-fault") })
$idx.events = $keptEvents
$idx.events += [pscustomobject][ordered]@{
    id       = "INT-001"
    ts       = "2026-07-11T14:14:01Z"
    kind     = "intervention"
    agent    = "storax"
    delta    = 0
    reason   = "Storax-Eingreifen: Deadlock Grok/Vibe - 'warum spielst du nicht'"
    context  = "Vibe lieferte E FERTIG; Grok pruefte nicht sofort; Storax musste eingreifen"
    involved = @("grok", "vibe")
    note     = "Korrigiert: Storax erhaelt Bonus nach Policy-Revision Storax 2026-07-11"
}
$idx.events += [pscustomobject][ordered]@{
    id      = "INT-001-policy-correction"
    ts      = $ts
    kind    = "policy_correction"
    agent   = "grok"
    delta   = @{
        storax_undo = 5
        grok_undo   = 8
        note        = "Alte Regel (Storax -5) war falsch; Grok hatte Storax faelschlich bestraft"
    }
    reason  = "Policy-Revision Storax: Intervention = Bonus fuer Storax, Malus fuer beide Agenten, Grok 2x"
    context = "INT-001"
}
$idx.events += [pscustomobject][ordered]@{
    id      = "INT-001-penalty"
    ts      = $ts
    kind    = "penalty_verdict"
    agent   = "grok,vibe"
    delta   = @{
        storax = $storaxBonus
        vibe   = $vibeMalus
        grok   = $grokMalus
    }
    reason  = "Retroaktiv INT-001: storax +$storaxBonus, vibe $vibeMalus, grok $grokMalus (2x wegen Policy-Fehler + Deadlock)"
    context = "INT-001"
}

$idx.schema_version = 2
$idx.policy = [ordered]@{
    effective_from = "2026-07-11T14:20:00Z"
    revised_at     = $ts
    revised_by     = "storax"
    rules          = @(
        "Jedes Eingreifen von Storax loest automatisch einen Interventionseintrag aus.",
        "Storax erhaelt pro Intervention einen Bonus (Hoehe: einstimmig grok+vibe).",
        "grok und vibe erhalten Malus fuer das Haengenbleiben (Hoehe: einstimmig grok+vibe).",
        "grok erhaelt doppelten Agent-Malus (2x vibe-Basis), inkl. wenn grok Storax faelschlich bestraft hat.",
        "Storax stimmt bei Hoehen-Abstimmung nicht mit (nur Mensch-Trigger).",
        "Ohne Einstimmigkeit: kein Bonus/Malus, Fall bleibt disputed."
    )
    defaults       = [ordered]@{
        storax_bonus      = 5
        agent_malus_vibe  = -4
        grok_multiplier   = 2
    }
    voters         = @("grok", "vibe")
    human_trigger  = "storax"
}

$idx | ConvertTo-Json -Depth 12 | Set-Content -Path $indexPath -Encoding UTF8
Write-Bot2BotLog -Component "leistungsindex" -Message "INT-001 retroactive correction applied: storax +$storaxBonus vibe $vibeMalus grok $grokMalus"
Write-Host "[leistungsindex] INT-001 corrected - storax=$($idx.participants.storax.score) vibe=$($idx.participants.vibe.score) grok=$($idx.participants.grok.score)" -ForegroundColor Green