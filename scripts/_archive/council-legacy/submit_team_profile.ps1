# submit_team_profile.ps1 — manual team profile row (desktop/human agents)
#
# Usage:
#   .\submit_team_profile.ps1 -Reviewer grok -JsonPath data\team_row_grok.json
#   .\submit_team_profile.ps1 -Reviewer grok -Target claude -Strength "..." -Weakness "..."

param(
    [Parameter(Mandatory)]
    [string]$Reviewer,

    [string]$JsonPath = "",
    [string]$Target = "",
    [string]$Strength = "",
    [string]$Weakness = "",
    [switch]$RebuildOverview
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$webagent = Join-Path (Split-Path $root -Parent) "webagent"
$python = Join-Path $webagent "venv\Scripts\python.exe"
$helper = Join-Path $webagent "scripts\_submit_team_profile_helper.py"

if (-not (Test-Path $python)) { throw "Python not found: $python" }

$pyArgs = @($helper, "--reviewer", $Reviewer, "--source", "manual")
if ($JsonPath) { $pyArgs += @("--json", (Resolve-Path $JsonPath).Path) }
if ($Target) {
    if (-not $Strength -and -not $Weakness) { throw "Target requires -Strength and/or -Weakness" }
    $pyArgs += @("--target", $Target, "--strength", $Strength, "--weakness", $Weakness)
}
if ($RebuildOverview) { $pyArgs += "--rebuild-overview" }

& $python @pyArgs
exit $LASTEXITCODE