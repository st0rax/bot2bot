# team_profile.ps1 — Leistungsindex v3 team matrix
param(
    [string]$Reviewer = "",
    [string]$Reviewers = "",
    [double]$Timeout = 240,
    [switch]$Headed,
    [switch]$DryRun,
    [switch]$List,
    [switch]$OverviewOnly
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$webagent = Join-Path (Split-Path $root -Parent) "webagent"
$python = Join-Path $webagent "venv\Scripts\python.exe"
$script = Join-Path $webagent "scripts\run_team_profile_matrix.py"

if (-not (Test-Path $python)) { throw "Python not found: $python" }

if ($OverviewOnly) {
    & $python (Join-Path $webagent "scripts\leistungsindex_team.py") 2>$null
    $init = Join-Path $webagent "scripts\build_team_overview.py"
    if (Test-Path $init) { & $python $init; exit $LASTEXITCODE }
    & $python $script -RebuildOverview
    exit $LASTEXITCODE
}

$args = @($script)
if ($List) { $args += "--list" }
if ($Reviewer) { $args += @("--reviewer", $Reviewer) }
if ($Reviewers) { $args += @("--reviewers", $Reviewers) }
if ($Timeout -gt 0) { $args += @("--timeout", $Timeout) }
if ($Headed) { $args += "--headed" }
if ($DryRun) { $args += "--dry-run" }
$args += "--rebuild-overview"

$env:WEBAGENT_USE_SHARED_BROWSER = "1"
& $python @args
exit $LASTEXITCODE