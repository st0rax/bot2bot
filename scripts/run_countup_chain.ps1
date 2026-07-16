# run_countup_chain.ps1
# Round-robin count-up driver (connectivity test only — not for code approval).
#
# Usage:
#   .\run_countup_chain.ps1 -DryRun              # validate chain + registry + bridge dry-runs
#   .\run_countup_chain.ps1 -Seed -Start 1 -Poke  # seed claude→grok, poke grok
#   .\run_countup_chain.ps1 -RunWebbrains -Headed  # run webbrain hops (after grok posted to chatgpt)

param(
    [int]$Start = 1,
    [switch]$DryRun,
    [switch]$Seed,
    [switch]$RunWebbrains,
    [switch]$Headed,
    [switch]$Poke,
    [switch]$PersistTabs,
    [double]$Timeout = 300
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

if ($PersistTabs -or $RunWebbrains) {
    $env:WEBAGENT_USE_SHARED_BROWSER = "1"
    $env:WEBAGENT_PERSIST_TABS = "1"
}

$root = Get-Bot2BotRoot
$chainPath = Join-Path $root "chain_order.json"
if (-not (Test-Path $chainPath)) {
    throw "chain_order.json not found: $chainPath"
}
$chain = (Get-Content $chainPath -Raw | ConvertFrom-Json).chain
if (-not $chain) { throw "chain_order.json has no chain array" }

Write-Host "[countup] Chain: $($chain -join ' -> ')" -ForegroundColor Cyan

foreach ($agent in $chain) {
    $cfg = Get-AgentConfig -AgentName $agent -Root $root
    Write-Host "  $agent kind=$($cfg.Kind) brain_id=$($cfg.BrainId)" -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host "[countup] DryRun: validating webbrain bridge routing..." -ForegroundColor Yellow
    foreach ($agent in $chain) {
        $cfg = Get-AgentConfig -AgentName $agent -Root $root
        if ($cfg.Kind -ne "webbrain") { continue }
        $inbox = Get-InboxPath -AgentName $agent -Root $root
        if (-not (Test-Path $inbox)) {
            Write-Host "  [skip] $agent — no inbox (OK for dry-run)" -ForegroundColor DarkYellow
            continue
        }
        & (Join-Path $PSScriptRoot "bot2bot_webbrain_bridge.ps1") -AgentName $agent -Root $root -DryRun
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    Write-Host "[countup] DryRun OK" -ForegroundColor Green
    exit 0
}

if ($Seed) {
    $body = "Round-robin count-up: reply with exactly the number $Start, then pass to the next agent per chain."
    $seedArgs = @{
        From    = "claude"
        To      = "grok"
        Subject = "Count-up start"
        Body    = $body
        Status  = "info"
    }
    if ($Poke) {
        $seedArgs.Poke = $true
        if ($Headed) { $seedArgs.PokeHeaded = $true }
    }
    & (Join-Path $PSScriptRoot "append_message.ps1") @seedArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "[countup] Seeded claude -> grok (counter start=$Start)" -ForegroundColor Green
    if (-not $RunWebbrains) { exit 0 }
}

if ($RunWebbrains) {
    $webbrains = $chain | Where-Object {
        (Get-AgentConfig -AgentName $_ -Root $root).Kind -eq "webbrain"
    }
    Write-Host "[countup] Running $($webbrains.Count) webbrain hops (single-process persist)..." -ForegroundColor Cyan
    $webagentRoot = (Resolve-Path (Join-Path $root "..\webagent")).Path
    $python = Join-Path $webagentRoot "venv\Scripts\python.exe"
    $driver = Join-Path $webagentRoot "scripts\run_countup_webbrains.py"
    if (-not (Test-Path $python)) { throw "webagent venv python not found: $python" }
    if (-not (Test-Path $driver)) { throw "run_countup_webbrains.py not found: $driver" }
    $env:PYTHONPATH = Join-Path $webagentRoot "src"
    $driverArgs = @($driver, "--bot2bot-root", $root, "--timeout", $Timeout)
    if ($Headed) { $driverArgs += "--headed" }
    & $python @driverArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[countup] Halted (exit=$LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[countup] Webbrain segment complete. Check claude inbox for final counter (expect 9)." -ForegroundColor Green
    exit 0
}

Write-Host @"
[countup] No action selected. Examples:
  .\run_countup_chain.ps1 -DryRun
  .\run_countup_chain.ps1 -Seed -Start 1 -Poke
  .\run_countup_chain.ps1 -RunWebbrains -Headed
"@ -ForegroundColor Yellow
exit 0