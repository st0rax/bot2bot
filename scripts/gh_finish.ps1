# gh_finish.ps1 — auth + release + URL update (ein Durchlauf)
param([string]$Version = "0.1.0")

$ErrorActionPreference = "Stop"
$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (Test-Path $chrome) {
    $env:GH_BROWSER = "`"$chrome`""
    $env:BROWSER = "`"$chrome`""
}

$root = Split-Path $PSScriptRoot -Parent
$zip = Join-Path $root "dist\webagent-suite_v$Version.zip"
$py = "C:\Users\storax\Desktop\webagent\venv\Scripts\python.exe"
$devicePy = Join-Path $root "data\_gh_device_win32.py"

Get-Process gh -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue

# --- 1) Auth ---
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[1/4] gh device auth ..." -ForegroundColor Cyan
    $authJob = Start-Job -ScriptBlock {
        $env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key 2>&1
    }

    $code = $null
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Milliseconds 600
        $all = (Receive-Job $authJob 2>&1 | Out-String)
        if ($all -match 'one-time code:\s*([A-Z0-9]{4}-[A-Z0-9]{4})') {
            $code = $Matches[1]
            break
        }
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $code = "SKIP"; break }
    }

    if (-not $code) {
        Stop-Job $authJob -EA SilentlyContinue
        Remove-Job $authJob -Force -EA SilentlyContinue
        throw "Kein Device-Code von gh erhalten"
    }

    if ($code -ne "SKIP") {
        Write-Host "      Code: $code" -ForegroundColor Yellow
        $env:PYTHONPATH = Join-Path $root "data"
        & $py $devicePy $code
        if ($LASTEXITCODE -ne 0) { throw "Device-UI fehlgeschlagen" }
    }

    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
    }
    Stop-Job $authJob -EA SilentlyContinue
    Remove-Job $authJob -Force -EA SilentlyContinue
    gh auth status
    if ($LASTEXITCODE -ne 0) { throw "gh nicht authentifiziert — im Browser Authorize klicken" }
}

$user = gh api user -q .login
Write-Host "[2/4] User: $user" -ForegroundColor Green

# --- 2) Repo ---
$repo = "$user/webagent"
gh repo view $repo 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[3/4] Repo anlegen ..." -ForegroundColor Cyan
    gh repo create webagent --public --description "WebAgent installer" --confirm | Out-Null
}

# --- 3) Release ---
$tag = "v$Version"
$zipName = Split-Path $zip -Leaf
gh release view $tag -R $repo 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    gh release create $tag $zip -R $repo --title $tag --notes "WebAgent online install"
} else {
    gh release upload $tag $zip -R $repo --clobber
}
if ($LASTEXITCODE -ne 0) { throw "Release upload fehlgeschlagen" }

$url = "https://github.com/$user/webagent/releases/download/$tag/$zipName"
Write-Host "[4/4] URL: $url" -ForegroundColor Green

foreach ($f in @(
    (Join-Path $root "dist\install-webagent.ps1"),
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "install-webagent.ps1")
)) {
    if (Test-Path $f) {
        (Get-Content $f -Raw) -replace '\$DefaultReleaseUrl = "[^"]*"', "`$DefaultReleaseUrl = `"$url`"" |
            Set-Content $f -Encoding UTF8
    }
}

$mf = Join-Path $root "dist\release_manifest.json"
if (Test-Path $mf) {
    $m = Get-Content $mf -Raw | ConvertFrom-Json
    $m.release_url_template = $url
    $m | ConvertTo-Json -Depth 3 | Set-Content $mf -Encoding UTF8
}

$t = Join-Path $env:TEMP "wa_dl_test.zip"
Invoke-WebRequest -Uri $url -OutFile $t -UseBasicParsing
Write-Host "Download-Test OK ($([math]::Round((Get-Item $t).Length/1KB)) KB)" -ForegroundColor Green
Remove-Item $t -Force -EA SilentlyContinue
Write-Output $url