# submit_vibe_ballot.ps1 — vibe self_submitted council ballots (run FROM vibe tab only)
param(
    [string]$BodyPath = "",
    [string]$InReplyTo = "3888b40e-c481-4040-96eb-503065423148"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

if (-not $BodyPath) {
    $BodyPath = Join-Path (Get-Bot2BotRoot) "data\_vibe_ballot_submit_body.txt"
}
if (-not (Test-Path $BodyPath)) { throw "BodyPath not found: $BodyPath" }

$append = Join-Path $PSScriptRoot "append_message.ps1"
& $append -From vibe -To grok -Subject "Council Ballots (self_submitted)" -BodyPath $BodyPath -Status info -InReplyTo $InReplyTo -Poke

$py = Join-Path (Split-Path (Get-Bot2BotRoot) -Parent) "webagent\venv\Scripts\python.exe"
$ingest = Join-Path (Split-Path (Get-Bot2BotRoot) -Parent) "webagent\scripts\ingest_vibe_council_vote.py"
& $py $ingest --body-path $BodyPath --message-id "manual-vibe-submit"
Write-Host "[submit_vibe_ballot] OK — grok ingests on next watch cycle"