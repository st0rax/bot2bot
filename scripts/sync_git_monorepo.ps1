# sync_git_monorepo.ps1 — Desktop-Stand nach GitHub pushen (Monorepo-Layout)
#
#   .\sync_git_monorepo.ps1
# Layout im Repo (wie Release-ZIP):
#   bot2bot/
#   webagent/
#   install-webagent.ps1
#   install-webagent.cmd

param(
    [string]$Version = "",
    [string]$Repo = "webagent"
)

$ErrorActionPreference = "Stop"
$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

$git = "git"
$bot2botSrc = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$webagentSrc = Join-Path (Split-Path $bot2botSrc -Parent) "webagent"
$publishRoot = Join-Path $bot2botSrc "git-publish"

if (-not (Test-Path $webagentSrc)) { throw "webagent nicht gefunden: $webagentSrc" }

gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "gh nicht eingeloggt — zuerst gh auth login" }
$user = gh api user -q .login
$remote = "https://github.com/$user/$Repo.git"

function Copy-Project {
    param([string]$Src, [string]$Dst, [string[]]$ExcludeDir, [string[]]$ExcludeFile = @())
    $args = @($Src, $Dst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np")
    foreach ($d in $ExcludeDir) { $args += "/XD"; $args += $d }
    foreach ($f in $ExcludeFile) { $args += "/XF"; $args += $f }
    robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed $Src" }
}

function Remove-PublishNoise {
    param([string]$Root)
    $dropDirs = @(
        (Join-Path $Root "bot2bot\data"),
        (Join-Path $Root "bot2bot\inbox"),
        (Join-Path $Root "bot2bot\history"),
        (Join-Path $Root "webagent\data"),
        (Join-Path $Root "webagent\runtime"),
        (Join-Path $Root "webagent\src\webagent_agent.egg-info")
    )
    foreach ($d in $dropDirs) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    }
    $dropGlobs = @(
        (Join-Path $Root "webagent\*_PLAN.md"),
        (Join-Path $Root "webagent\TASK_*.md"),
        (Join-Path $Root "webagent\FULL_ANALYSIS*"),
        (Join-Path $Root "webagent\GENIUS_COUNCIL*"),
        (Join-Path $Root "webagent\*.txt"),
        (Join-Path $Root "webagent\events.jsonl"),
        (Join-Path $Root "bot2bot\MONOREPO_README.md"),
        (Join-Path $Root "bot2bot\git-publish.gitignore")
    )
    foreach ($g in $dropGlobs) {
        Get-Item $g -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $publishRoot) {
    Remove-Item $publishRoot -Recurse -Force
}
& $git clone $remote $publishRoot 2>$null
if ($LASTEXITCODE -ne 0) {
    New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null
}

Write-Host "[sync_git] publish -> $publishRoot" -ForegroundColor Cyan
Copy-Project $bot2botSrc (Join-Path $publishRoot "bot2bot") @("dist", "git-publish", ".git", "data", "inbox", "history")
$waExcludeFiles = @(
    "events.jsonl", "latest_claude_response.txt", ".grok_last_claude_check.txt",
    "FULL_ANALYSIS_SINCE_GROK_TAKEOVER.txt", "GENIUS_COUNCIL_EVALUATION.txt",
    "STANDING_INSTRUCTION_FOR_CLAUDE.txt", "next_prompt_for_claude.txt"
)
Copy-Project $webagentSrc (Join-Path $publishRoot "webagent") @(
    "venv", ".git", "__pycache__", ".pytest_cache", "runs", "terminals",
    "shared", "_archive", "logs", "data", "runtime", "mcps", "agent-tools"
) $waExcludeFiles
Remove-PublishNoise $publishRoot
$dupDocs = Join-Path $publishRoot "docs\docs"
if (Test-Path $dupDocs) { Remove-Item $dupDocs -Recurse -Force }
$agentTools = Join-Path $publishRoot "webagent\agent-tools"
if (Test-Path $agentTools) { Remove-Item $agentTools -Recurse -Force }

foreach ($f in @("install-webagent.ps1", "install-webagent.cmd")) {
    $src = Join-Path ([Environment]::GetFolderPath("Desktop")) $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $publishRoot $f) -Force }
}

$readmeSrc = Join-Path $bot2botSrc "MONOREPO_README.md"
if (Test-Path $readmeSrc) {
    Copy-Item $readmeSrc (Join-Path $publishRoot "README.md") -Force
} else {
    throw "MONOREPO_README.md fehlt"
}

$docsSrc = Join-Path $bot2botSrc "docs"
if (Test-Path $docsSrc) {
    Copy-Item $docsSrc (Join-Path $publishRoot "docs") -Recurse -Force
}

$giSrc = Join-Path $bot2botSrc "git-publish.gitignore"
if (Test-Path $giSrc) {
    Copy-Item $giSrc (Join-Path $publishRoot ".gitignore") -Force
}

Push-Location $publishRoot
try {
    if (-not (Test-Path ".git")) {
        & $git init
        & $git branch -M main
        & $git remote add origin $remote
    }

    if (-not (& $git config user.email 2>$null)) {
        & $git config user.email "$user@users.noreply.github.com"
        & $git config user.name $user
    }

    & $git add -A
    $msg = if ($Version) { "sync release v$Version" } else { "sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    & $git commit -m $msg
    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed"
    } else {
        & $git push -u origin main
        if ($LASTEXITCODE -ne 0) { throw "git push failed" }
        Write-Host "[sync_git] pushed -> $remote" -ForegroundColor Green
    }
} finally {
    Pop-Location
}