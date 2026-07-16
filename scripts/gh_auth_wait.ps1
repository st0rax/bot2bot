$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "[gh] OAuth web login — bitte im Browser auf Authorize klicken falls noetig" -ForegroundColor Cyan
$job = Start-Job -ScriptBlock {
    $env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key 2>&1
}

Start-Sleep -Seconds 4
Receive-Job $job | ForEach-Object { Write-Host $_ }

for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 3
    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[gh] AUTH_OK" -ForegroundColor Green
        gh auth status
        gh api user -q .login
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        exit 0
    }
    $out = Receive-Job $job 2>&1
    if ($out) { $out | ForEach-Object { Write-Host $_ } }
}

Receive-Job $job 2>&1 | ForEach-Object { Write-Host $_ }
Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -Force -ErrorAction SilentlyContinue
Write-Host "[gh] AUTH_TIMEOUT" -ForegroundColor Red
exit 1