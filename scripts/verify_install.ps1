# verify_install.ps1 — Post-install smoke checks
#
#   .\verify_install.ps1                    # lenient (empty profile OK)
#   .\verify_install.ps1 -Strict            # after login: profile must be populated
#   .\verify_install.ps1 -WebagentRoot C:\path\to\webagent -Full

param(
    [string]$WebagentRoot = "",
    [string]$Bot2BotRoot = "",
    [switch]$Full,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = if ($Bot2BotRoot) { $Bot2BotRoot } else { Get-Bot2BotRoot }
if (-not $WebagentRoot) {
    $WebagentRoot = Join-Path (Split-Path $root -Parent) "webagent"
    $link = Join-Path $WebagentRoot "data\install_bot2bot_root.txt"
    if (Test-Path $link) {
        $root = (Get-Content $link -Raw).Trim()
    }
}

$failures = @()

function Test-Check {
    param([string]$Name, [scriptblock]$Block)
    try {
        & $Block
        Write-Host "[OK] $Name" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] $Name - $_" -ForegroundColor Red
        $script:failures += $Name
    }
}

Write-Host "=== verify_install ===" -ForegroundColor Cyan
Write-Host "bot2bot:  $root"
Write-Host "webagent: $WebagentRoot"
Write-Host ""

Test-Check "registry.json" {
    $r = Get-AgentRegistry -Root $root
    if (-not $r) { throw "empty registry" }
}

Test-Check "history writable" {
    $hp = Get-HistoryPath -Root $root
    $dir = Split-Path $hp -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

Test-Check "install_manifest.json" {
    $mp = Join-Path $root "data\install_manifest.json"
    if (-not (Test-Path $mp)) { throw "missing (run install_webagent.ps1)" }
    $m = Get-Content $mp -Raw | ConvertFrom-Json
    if ($m.suite_version) {
        Write-Host "       suite_version=$($m.suite_version)" -ForegroundColor DarkGray
    }
}

Test-Check "webagent venv python" {
    $py = Join-Path $WebagentRoot "venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { throw "not found: $py" }
}

Test-Check "shared profile dir" {
    $shared = Join-Path $WebagentRoot "data\profiles\shared"
    if (-not (Test-Path $shared)) { throw "missing: $shared" }
}

Test-Check "webagent cli --help" {
    $py = Join-Path $WebagentRoot "venv\Scripts\python.exe"
    $prevPath = $env:PYTHONPATH
    $env:PYTHONPATH = Join-Path $WebagentRoot "src"
    try {
        $out = & $py -m webagent.cli --help 2>&1
        if ($LASTEXITCODE -ne 0) { throw $out }
    } finally {
        $env:PYTHONPATH = $prevPath
    }
}

Test-Check "brains-health" {
    $py = Join-Path $WebagentRoot "venv\Scripts\python.exe"
    $prevPath = $env:PYTHONPATH
    $env:PYTHONPATH = Join-Path $WebagentRoot "src"
    $env:WEBAGENT_USE_SHARED_BROWSER = "1"
    $healthArgs = @("-m", "webagent.cli", "brains-health")
    if (-not $Strict) { $healthArgs += "--allow-empty-profile" }
    try {
        & $py @healthArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
    } finally {
        $env:PYTHONPATH = $prevPath
    }
}

Test-Check "pytest smoke" {
    $py = Join-Path $WebagentRoot "venv\Scripts\python.exe"
    $testTargets = if ($Full) { @("tests/") } else {
        @("tests/test_protocol.py", "tests/test_loop_guard.py", "tests/test_brains_health_cli.py")
    }
    Push-Location $WebagentRoot
    $env:PYTHONPATH = "src"
    try {
        & $py -m pytest @testTargets -q --tb=no 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "pytest exit $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

if ($Strict) {
    Test-Check "shared profile populated" {
        $shared = Join-Path $WebagentRoot "data\profiles\shared"
        $entries = Get-ChildItem $shared -Force -EA SilentlyContinue |
            Where-Object { $_.Name -notin @(".gitkeep") }
        if (-not $entries) { throw "empty - run webagent.bat login --brain chatgpt" }
    }
}

Test-Check "poke dry-run (grok)" {
    $registry = Get-AgentRegistry -Root $root
    if ($registry.PSObject.Properties.Name -notcontains "grok") {
        Write-Host "  (grok not in registry - skip)" -ForegroundColor DarkGray
        return
    }
    if (-not (Test-AgentIsActive -AgentName grok -Root $root)) {
        Write-Host "  (grok inactive - skip)" -ForegroundColor DarkGray
        return
    }
    & (Join-Path $PSScriptRoot "poke_agent.ps1") -AgentName grok -DryRun | Out-Null
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All checks passed." -ForegroundColor Green