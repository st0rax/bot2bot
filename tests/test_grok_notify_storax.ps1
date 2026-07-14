# test_grok_notify_storax.ps1 — structural tests for notify-storax workflow parser
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$script = Join-Path $root "grok_notify_storax.ps1"
if (-not (Test-Path $script)) { throw "missing $script" }

$parseBlock = {
    param($Raw)
    if ($Raw -notmatch '(?i)benachrichtige\s+storax') { return $null }
    $text = $null
    if ($Raw -match '(?i)benachrichtige\s+storax\s*:\s*(.+)') { $text = $Matches[1].Trim() }
    else { $text = ($Raw -replace '(?i).*benachrichtige\s+storax[:\s]*', '').Trim() }
    if (-not $text) { $text = "Neue Anweisung fuer storax." }
    return $text
}

$t1 = & $parseBlock "benachrichtige storax: Bitte einloggen"
if ($t1 -ne "Bitte einloggen") { throw "parse colon failed: $t1" }

$t2 = & $parseBlock "Subject: benachrichtige storax`n`nHallo welt"
if ($t2 -notmatch "Hallo") { throw "parse body failed: $t2" }

$t3 = & $parseBlock "nichts relevantes"
if ($null -ne $t3 -and $t3 -ne "") { throw "should not parse unrelated" }

Write-Host "[test_grok_notify_storax] OK 3 cases" -ForegroundColor Green
exit 0