# watch_vibe_ballot.ps1 — poll history for vibe self_submitted council ballots
param(
    [int]$IntervalSeconds = 20,
    [switch]$Once,
    [string]$SinceTs = "2026-07-11T19:50:00Z"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$history = Get-HistoryPath -Root $root
$py = Join-Path (Split-Path $root -Parent) "webagent\venv\Scripts\python.exe"
$ingest = Join-Path (Split-Path $root -Parent) "webagent\scripts\ingest_vibe_council_vote.py"
$outVote = Join-Path $root "data\vibe_council_vote.json"
$since = [datetime]::Parse($SinceTs).ToUniversalTime()

function Test-VibeBallot($msg) {
    return ($msg.body -match "P5\s*:") -or ($msg.body -match "INTEGRITY\s*:") -or ($msg.body -match "INT003\s*:")
}

function Invoke-Ingest($msg) {
    $bodyFile = Join-Path $root "data\_vibe_ballot_body_tmp.txt"
    Set-Content -Path $bodyFile -Value $msg.body -Encoding UTF8
    & $py $ingest --body-path $bodyFile --message-id $msg.id --out $outVote
    if ($LASTEXITCODE -ne 0) { throw "ingest failed exit=$LASTEXITCODE" }
}

function Invoke-Check {
    if (-not (Test-Path $history)) { return $false }
    $msgs = @(Get-Content $history | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ })
    $candidate = $msgs |
        Where-Object { $_.from -eq "vibe" -and $_.to -eq "grok" } |
        Where-Object { [datetime]::Parse($_.ts).ToUniversalTime() -ge $since } |
        Where-Object { Test-VibeBallot $_ } |
        Select-Object -Last 1
    if (-not $candidate) { return $false }
    if ((Test-Path $outVote) -and ((Get-Content $outVote -Raw | ConvertFrom-Json).message_id -eq $candidate.id)) {
        return $false
    }
    Write-Host "[watch_vibe_ballot] Ingesting $($candidate.id) '$($candidate.subject)'" -ForegroundColor Green
    Invoke-Ingest $candidate
    $summaryFile = Join-Path $root "data\_vibe_ballot_ingested.txt"
    @"
Vibe council vote ingested (self_submitted).
msg_id: $($candidate.id)
file: data/vibe_council_vote.json
next: merge into p5 + combined tallies
"@ | Set-Content $summaryFile -Encoding UTF8
    $append = Join-Path $PSScriptRoot "append_message.ps1"
    & $append -From grok -To claude -Subject "Vibe Council-Ballot eingegangen" -BodyPath $summaryFile -Status info -InReplyTo "091c2a66-4d5a-4752-ae16-04d51c6141ca"
    return $true
}

do {
    try {
        if (Invoke-Check) { if ($Once) { break } }
    } catch {
        Write-Host "[watch_vibe_ballot] error: $_" -ForegroundColor Red
    }
    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSeconds
} while ($true)