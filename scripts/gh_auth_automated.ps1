# gh_auth_automated.ps1 - nur github.com im Playwright-Shared-Profile oeffnen
$ErrorActionPreference = "Stop"
$py = "C:\Users\storax\Desktop\webagent\venv\Scripts\python.exe"
$sharedPy = "C:\Users\storax\Desktop\bot2bot\data\_gh_device_shared.py"

Write-Host "[gh_auth] shared profile -> github.com" -ForegroundColor Cyan
& $py $sharedPy | ForEach-Object { Write-Host $_ }
exit 0