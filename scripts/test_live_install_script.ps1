$ErrorActionPreference = "Stop"
$url = "https://github.com/alexanderkrenz89-ctrl/webagent/releases/download/v0.1.5/install-webagent.ps1"
$s = Invoke-RestMethod -Uri $url -TimeoutSec 120
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($s, [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { Write-Host $_ }; exit 1 }
if ($s -match '[^\x00-\x7F]') { Write-Host "NON-ASCII in live script"; exit 1 }
Write-Host "LIVE SCRIPT OK len=$($s.Length)"