# require_urteils_gate.ps1 — P5: prueft zweite Freigabe vor folgenreichen Aktionen
param(
    [Parameter(Mandatory)]
    [ValidateSet("ledger_penalty", "diff_merge", "moderator_appoint", "council_final", "release_tag")]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$GateAgent,

    [string]$GateRef = "",
    [string]$Detail = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$gateFile = Join-Path $root "data\urteils_gates"
if (-not (Test-Path $gateFile)) { New-Item -ItemType Directory -Path $gateFile -Force | Out-Null }

$slug = $GateAgent.ToLower()
if (-not (Test-AgentIsActive -AgentName $slug -Root $root)) {
    Write-Error "P5 BLOCK: Gate agent '$slug' inactive. Need another available reviewer (claude, mistral, storax)."
    exit 2
}

$record = [ordered]@{
    ts          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    action      = $Action
    gate_agent  = $slug
    gate_ref    = $GateRef
    detail      = $Detail
    policy      = "P5"
}
$path = Join-Path $gateFile "$Action`_$(Get-Date -Format 'yyyyMMddHHmmss').json"
$record | ConvertTo-Json | Set-Content $path -Encoding UTF8
Write-Host "[P5] Urteils-Gate OK: $Action via $slug -> $path" -ForegroundColor Green