# github_release_setup.ps1 — gh auth + release upload + URL update
param(
    [string]$Version = "0.1.0",
    [string]$RepoName = "webagent",
    [string]$ZipPath = ""
)

$ErrorActionPreference = "Stop"
$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$root = Split-Path $PSScriptRoot -Parent
if (-not $ZipPath) {
    $ZipPath = Join-Path $root "dist\webagent-suite_v$Version.zip"
}
if (-not (Test-Path $ZipPath)) {
    throw "ZIP not found: $ZipPath"
}

function Ensure-GhAuth {
    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }

    Write-Host "[github] Starting gh device auth ..." -ForegroundColor Cyan
    $authJob = Start-Job -ScriptBlock {
        $env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        @"
GitHub.com
HTTPS
Y
Login with a web browser

"@ | gh auth login 2>&1
    }

    $code = $null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        $out = Receive-Job $authJob 2>&1 | Out-String
        if ($out -match 'one-time code:\s*([A-Z0-9]{4}-[A-Z0-9]{4})') {
            $code = $Matches[1]
            break
        }
    }
    if (-not $code) {
        Stop-Job $authJob -ErrorAction SilentlyContinue
        Remove-Job $authJob -Force -ErrorAction SilentlyContinue
        throw "Could not read gh device code"
    }

    Write-Host "[github] Device code: $code" -ForegroundColor Yellow
    $uiScript = Join-Path $root "data\_github_ui_device.py"
    $py = "C:\Users\storax\Desktop\webagent\venv\Scripts\python.exe"
    & $py $uiScript $code

    Wait-Job $authJob -Timeout 120 | Out-Null
    $authOut = Receive-Job $authJob 2>&1 | Out-String
    Remove-Job $authJob -Force -ErrorAction SilentlyContinue
    Write-Host $authOut

    gh auth status
    if ($LASTEXITCODE -ne 0) { throw "gh auth failed — authorize device code in browser" }
}

Ensure-GhAuth

$user = gh api user -q .login
Write-Host "[github] User: $user" -ForegroundColor Green

$repo = "$user/$RepoName"
$view = gh repo view $repo 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[github] Creating repo $repo ..." -ForegroundColor Cyan
    gh repo create $RepoName --public --description "WebAgent — brain-independent local agent" --confirm
    if ($LASTEXITCODE -ne 0) { throw "repo create failed" }
}

$tag = "v$Version"
$rel = gh release view $tag -R $repo 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[github] Creating release $tag ..." -ForegroundColor Cyan
    gh release create $tag $ZipPath -R $repo --title $tag --notes "WebAgent suite online installer release"
    if ($LASTEXITCODE -ne 0) { throw "release create failed" }
} else {
    Write-Host "[github] Release exists, uploading asset ..." -ForegroundColor Cyan
    gh release upload $tag $ZipPath -R $repo --clobber
    if ($LASTEXITCODE -ne 0) { throw "release upload failed" }
}

$zipName = Split-Path $ZipPath -Leaf
$url = "https://github.com/$user/$RepoName/releases/download/$tag/$zipName"
Write-Host "[github] Release URL: $url" -ForegroundColor Green

$targets = @(
    (Join-Path $root "dist\install-webagent.ps1"),
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "install-webagent.ps1")
)
foreach ($f in $targets) {
    if (Test-Path $f) {
        (Get-Content $f -Raw) -replace '\$DefaultReleaseUrl = "[^"]*"', "`$DefaultReleaseUrl = `"$url`"" |
            Set-Content $f -Encoding UTF8 -NoNewline
        Write-Host "[github] Updated $f"
    }
}

$manifestPath = Join-Path $root "dist\release_manifest.json"
if (Test-Path $manifestPath) {
    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $m.release_url_template = $url
    $m | ConvertTo-Json -Depth 3 | Set-Content $manifestPath -Encoding UTF8
}

# Quick download test
$testZip = Join-Path $env:TEMP "webagent_release_test.zip"
Invoke-WebRequest -Uri $url -OutFile $testZip -UseBasicParsing
$dlMb = [math]::Round((Get-Item $testZip).Length / 1MB, 2)
Write-Host "[github] Download test OK ($dlMb MB)" -ForegroundColor Green
Remove-Item $testZip -Force -ErrorAction SilentlyContinue

Write-Output $url