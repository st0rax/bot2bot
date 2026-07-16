# claude_deputy_review.ps1
# Invoke webagent deputy review when Claude Desktop is absent.
#
# Usage:
#   .\claude_deputy_review.ps1 -Task rankings -RunId live021r4 -Brain chatgpt -PostInbox
#   .\claude_deputy_review.ps1 -Task diff -DiffPath ..\..\webagent\PROPOSED_DIFF_026_*.txt -Brain kimi
#   .\claude_deputy_review.ps1 -Task rankings -Brain chatgpt -Brain kimi -PostInbox

param(
    [Parameter(Mandatory)]
    [ValidateSet("rankings", "diff", "proposal")]
    [string]$Task,

    [string]$ProposalPath = "",
    [string]$OutJson = "",

    [string]$RunId = "live021r4",
    [string]$DiffPath = "",
    [string[]]$Brain = @("chatgpt"),
    [string]$InReplyTo = "",
    [double]$Timeout = 180,
    [switch]$Headed,
    [switch]$PostInbox,
    [string]$To = "grok"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$webagent = Join-Path (Split-Path $root -Parent) "webagent"
$python = Join-Path $webagent "venv\Scripts\python.exe"
$script = Join-Path $webagent "scripts\run_deputy_review.py"
$outDir = Join-Path $root "data\deputy_reviews"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
if (-not $OutJson) {
    $OutJson = Join-Path $outDir "deputy_${Task}_${stamp}.json"
}
$outJson = $OutJson

if (-not (Test-Path $python)) { throw "Python not found: $python" }
if (-not (Test-Path $script)) { throw "run_deputy_review.py not found: $script" }

$deputyPath = Join-Path $root "data\claude_deputy.json"
if (-not (Test-Path $deputyPath)) {
    Write-Host "[claude_deputy_review] WARNING: claude_deputy.json missing" -ForegroundColor Yellow
}

$pyArgs = @(
    $script,
    "--task", $Task,
    "--timeout", $Timeout,
    "--out", $outJson
)
$brainList = @($Brain | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($brainList.Count -gt 1) {
    $pyArgs += @("--brains", ($brainList -join ','))
} elseif ($brainList.Count -eq 1) {
    $pyArgs += @("--brain", $brainList[0])
} else {
    $pyArgs += @("--brain", "chatgpt")
}
if ($Task -eq "rankings") { $pyArgs += @("--run-id", $RunId) }
if ($Task -eq "diff" -and $DiffPath) { $pyArgs += @("--diff-path", $DiffPath) }
if ($Task -eq "proposal" -and $ProposalPath) { $pyArgs += @("--proposal-path", $ProposalPath) }
if ($InReplyTo) { $pyArgs += @("--in-reply-to", $InReplyTo) }
if ($Headed) { $pyArgs += "--headed" }
if ($PostInbox) { $pyArgs += @("--post-inbox", "--to", $To) }

$env:PYTHONPATH = Join-Path $webagent "src"
# Shared profile often locked if Chrome open — council uses isolated launches
$env:WEBAGENT_USE_SHARED_BROWSER = "0"
$env:WEBAGENT_PERSIST_TABS = "0"

$brainLabel = $brainList -join ','
Write-Host "[claude_deputy_review] task=$Task brains=$brainLabel -> $outJson" -ForegroundColor Cyan
& $python @pyArgs
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host "[claude_deputy_review] exit $code" -ForegroundColor Red
    exit $code
}

if (Test-Path $outJson) {
    $result = Get-Content $outJson -Raw | ConvertFrom-Json
    Write-Host "[claude_deputy_review] results:" -ForegroundColor Green
    foreach ($r in $result.results) {
        $v = if ($r.ok) { $r.verdict } else { "FAIL($($r.error))" }
        Write-Host "  $($r.brain): $v — $($r.reason)"
    }
}
Write-Output $outJson