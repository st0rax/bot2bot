# run_proposal_council.ps1 — Alle WebBrains reviewen PROP_SYS_001
#
#   .\run_proposal_council.ps1
#   .\run_proposal_council.ps1 -Timeout 120

param(
    [double]$Timeout = 150,
    [switch]$SkipSynthesis
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$proposal = Join-Path $root "data\proposals\PROP_SYS_001_desktop_hygiene.md"
$allBrains = "chatgpt,deepseek,kimi,gemini,qwen,mistral,claude,zai"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$outJson = Join-Path $root "data\deputy_reviews\prop_sys001_council_$stamp.json"

Write-Host "=== Proposal Council: PROP_SYS_001 ===" -ForegroundColor Cyan
Write-Host "Brains: $allBrains"
Write-Host "Timeout: ${Timeout}s per brain"
Write-Host ""

& (Join-Path $PSScriptRoot "claude_deputy_review.ps1") `
    -Task proposal `
    -ProposalPath $proposal `
    -Brain $allBrains.Split(",") `
    -Timeout $Timeout `
    -OutJson $outJson `
    -PostInbox `
    -To grok

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Some brains failed — synthesis uses partial results"
}

if (-not $SkipSynthesis) {
    & (Join-Path $PSScriptRoot "finalize_prop_sys001.ps1") -ReviewJson $outJson
}