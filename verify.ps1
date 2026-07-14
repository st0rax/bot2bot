#Requires -Version 5.1
# verify.ps1 — smoke test for bot2bot core (register + send + inbox file)
$ErrorActionPreference = "Stop"
$root = if ($env:BOT2BOT_ROOT) { $env:BOT2BOT_ROOT } else { Split-Path $MyInvocation.MyCommand.Path }
$testSlug = "verifytest"
$reg = Join-Path $root "register.ps1"
$send = Join-Path $root "send.ps1"
if (-not (Test-Path $reg)) { throw "register.ps1 fehlt" }
if (-not (Test-Path $send)) { throw "send.ps1 fehlt" }
$agentDir = Join-Path (Join-Path $root "agents") $testSlug
if (Test-Path $agentDir) { Remove-Item $agentDir -Recurse -Force }
& $reg -Name $testSlug | Out-Null
& $send -To $testSlug -From verify -Subject "smoke" -Message "verify ok" | Out-Null
$inbox = Join-Path $agentDir "inbox"
$files = Get-ChildItem $inbox -Filter "*.msg.txt"
if ($files.Count -lt 1) { throw "Keine Nachricht in inbox" }
$content = Get-Content $files[0].FullName -Raw
if ($content -notmatch "verify ok") { throw "Nachrichteninhalt falsch" }
Remove-Item $agentDir -Recurse -Force
Write-Host "[verify] OK — register, send, inbox" -ForegroundColor Green
exit 0