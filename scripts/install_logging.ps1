# install_logging.ps1 - Install transcript + GitHub issue on failure (ASCII only)
#
#   . .\install_logging.ps1
#   $session = Start-InstallLog -Component install-webagent -Version 0.1.7 -InstallRoot C:\Ziel
#   try { ...; Complete-InstallLog -Session $session } catch { Report-InstallFailure -Session $session -ErrorRecord $_; exit 1 }

function Get-InstallLogDir {
    param(
        [string]$InstallRoot = "",
        [string]$Bot2BotRoot = ""
    )
    if ($Bot2BotRoot -and (Test-Path -LiteralPath $Bot2BotRoot)) {
        return Join-Path $Bot2BotRoot "data\install_logs"
    }
    if ($InstallRoot) {
        $bb = Join-Path $InstallRoot "bot2bot"
        if (Test-Path -LiteralPath $bb) {
            return Join-Path $bb "data\install_logs"
        }
    }
    return Join-Path $env:TEMP "webagent_install_logs"
}

function Get-InstallWatchDir {
    param(
        [string]$InstallRoot = "",
        [string]$Bot2BotRoot = ""
    )
    if ($Bot2BotRoot -and (Test-Path -LiteralPath $Bot2BotRoot)) {
        return Join-Path $Bot2BotRoot "data\watch"
    }
    if ($InstallRoot) {
        $bb = Join-Path $InstallRoot "bot2bot"
        if (Test-Path -LiteralPath $bb) {
            return Join-Path $bb "data\watch"
        }
    }
    return Join-Path $env:TEMP "webagent_install_watch"
}

function Get-InstallMachineInfo {
    $os = [System.Environment]::OSVersion.VersionString
    $ps = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $user = $env:USERNAME
    $hostName = $env:COMPUTERNAME
    return [pscustomobject]@{
        hostname = $hostName
        user     = $user
        os       = $os
        pwsh     = $ps
        cwd      = (Get-Location).Path
    }
}

function Resolve-InstallLoggingScript {
    param([string]$Version = "0.1.10")
    $local = Join-Path $PSScriptRoot "install_logging.ps1"
    if (Test-Path -LiteralPath $local) { return $local }

    $cached = Join-Path $env:TEMP "install_logging_v$Version.ps1"
    if (Test-Path -LiteralPath $cached) { return $cached }

    $urls = @(
        "https://github.com/st0rax/webagent/releases/download/v$Version/install_logging.ps1"
    )
    foreach ($url in $urls) {
        try {
            $null = Invoke-WebRequest -Uri $url -OutFile $cached -UseBasicParsing -TimeoutSec 60
            if ((Get-Item $cached).Length -gt 200) { return $cached }
        } catch {
            Write-Host "[install-log] download failed: $url" -ForegroundColor Yellow
        }
    }
    return $null
}

function Start-InstallLog {
    param(
        [Parameter(Mandatory)][string]$Component,
        [string]$Version = "",
        [string]$InstallRoot = "",
        [string]$Bot2BotRoot = "",
        [string]$Repo = "st0rax/webagent"
    )
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logDir = Get-InstallLogDir -InstallRoot $InstallRoot -Bot2BotRoot $Bot2BotRoot
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $logFile = Join-Path $logDir "install_${stamp}.log"
    $latest = Join-Path $logDir "latest_install.log"
    $info = Get-InstallMachineInfo

    $header = @(
        "=== WebAgent Install Log ===",
        "started: $((Get-Date).ToUniversalTime().ToString('o'))",
        "component: $Component",
        "version: $Version",
        "install_root: $InstallRoot",
        "bot2bot_root: $Bot2BotRoot",
        "hostname: $($info.hostname)",
        "user: $($info.user)",
        "os: $($info.os)",
        "powershell: $($info.pwsh)",
        "cwd: $($info.cwd)",
        "log_file: $logFile",
        "===========================",
        ""
    ) -join "`r`n"
    Set-Content -LiteralPath $logFile -Value $header -Encoding UTF8

    $transcriptOn = $false
    try {
        Start-Transcript -LiteralPath $logFile -Append -Force | Out-Null
        $transcriptOn = $true
    } catch {
        Add-Content -LiteralPath $logFile -Value "[warn] Start-Transcript failed: $($_.Exception.Message)" -Encoding UTF8
    }

    try {
        Copy-Item -LiteralPath $logFile -Destination $latest -Force
    } catch { }

    Write-Host "[install-log] logging -> $logFile" -ForegroundColor DarkCyan

    return [pscustomobject]@{
        component     = $Component
        version       = $Version
        install_root  = $InstallRoot
        bot2bot_root  = $Bot2BotRoot
        repo          = $Repo
        started       = (Get-Date).ToUniversalTime().ToString("o")
        stamp         = $stamp
        log_dir       = $logDir
        log_file      = $logFile
        latest_log    = $latest
        transcript_on = $transcriptOn
        machine       = $info
    }
}

function Stop-InstallTranscript {
    param($Session)
    if (-not $Session) { return }
    if ($Session.transcript_on) {
        try { Stop-Transcript | Out-Null } catch { }
        $Session.transcript_on = $false
    }
    try {
        if (Test-Path -LiteralPath $Session.log_file) {
            Copy-Item -LiteralPath $Session.log_file -Destination $Session.latest_log -Force
        }
    } catch { }
}

function Get-InstallLogTail {
    param(
        [string]$LogFile,
        [int]$Lines = 80
    )
    if (-not (Test-Path -LiteralPath $LogFile)) { return "(log file missing)" }
    $all = Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue
    if (-not $all) { return "(empty log)" }
    if ($all.Count -le $Lines) { return ($all -join "`n") }
    return ($all | Select-Object -Last $Lines) -join "`n"
}

function New-InstallFailureBody {
    param(
        $Session,
        $ErrorRecord,
        [string]$LogTail
    )
    $err = if ($ErrorRecord) {
        if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { "$ErrorRecord" }
    } else { "(unknown error)" }

    $stack = ""
    if ($ErrorRecord -and $ErrorRecord.ScriptStackTrace) {
        $stack = "`n`nStack:`n$($ErrorRecord.ScriptStackTrace)"
    }

    return @"
## Install failure

| Field | Value |
|-------|-------|
| Component | $($Session.component) |
| Version | $($Session.version) |
| Host | $($Session.machine.hostname) |
| User | $($Session.machine.user) |
| Install root | $($Session.install_root) |
| Started | $($Session.started) |
| Log | ``$($Session.log_file)`` |

### Error
``````
$err$stack
``````

### Log tail (last lines)
``````
$LogTail
``````

_Auto-generated by WebAgent installer._
"@
}

function New-GitHubIssueUrl {
    param(
        [string]$Repo,
        [string]$Title,
        [string]$Body
    )
    $t = [uri]::EscapeDataString($Title)
    $b = [uri]::EscapeDataString($Body)
    return "https://github.com/$Repo/issues/new?title=$t&body=$b"
}

function New-InstallGitHubIssue {
    param(
        $Session,
        [string]$Title,
        [string]$Body,
        [string[]]$Labels = @("install-failure", "bug")
    )
    $repo = $Session.repo
    $issueUrl = ""
    $issueNum = $null

    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $labelArgs = @()
        foreach ($l in $Labels) { $labelArgs += "--label"; $labelArgs += $l }
        $bodyFile = Join-Path $env:TEMP "wa_install_issue_$($Session.stamp).md"
        Set-Content -LiteralPath $bodyFile -Value $Body -Encoding UTF8
        try {
            $out = gh issue create -R $repo --title $Title --body-file $bodyFile @labelArgs 2>&1
            if ($LASTEXITCODE -eq 0 -and $out) {
                $issueUrl = [string]$out
                if ($issueUrl -match '/issues/(\d+)') { $issueNum = [int]$Matches[1] }
                Write-Host "[install-log] GitHub issue: $issueUrl" -ForegroundColor Green
            }
        } catch {
            Write-Host "[install-log] gh issue create failed: $_" -ForegroundColor Yellow
        } finally {
            Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $issueUrl) {
        $issueUrl = New-GitHubIssueUrl -Repo $repo -Title $Title -Body $Body
        Write-Host "[install-log] gh not available - open issue in browser:" -ForegroundColor Yellow
        Write-Host "  $issueUrl" -ForegroundColor Cyan
    }
    return [pscustomobject]@{ url = $issueUrl; number = $issueNum; via_gh = ($issueNum -ne $null) }
}

function Write-InstallWatchMarker {
    param(
        $Session,
        [string]$Status,
        $ErrorRecord = $null,
        $Issue = $null
    )
    $watchDir = Get-InstallWatchDir -InstallRoot $Session.install_root -Bot2BotRoot $Session.bot2bot_root
    New-Item -ItemType Directory -Path $watchDir -Force | Out-Null

    $err = ""
    if ($ErrorRecord) {
        $err = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { "$ErrorRecord" }
    }

    $marker = @{
        status       = $Status
        component    = $Session.component
        version      = $Session.version
        install_root = $Session.install_root
        hostname     = $Session.machine.hostname
        user         = $Session.machine.user
        started      = $Session.started
        finished     = (Get-Date).ToUniversalTime().ToString("o")
        log_file     = $Session.log_file
        error        = $err
        issue_url    = if ($Issue) { $Issue.url } else { "" }
        issue_number = if ($Issue -and $Issue.number) { $Issue.number } else { $null }
    }
    $json = $marker | ConvertTo-Json -Depth 4
    $path = Join-Path $watchDir "install_$($Session.stamp).json"
    $latest = Join-Path $watchDir "install_latest.json"
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    Set-Content -LiteralPath $latest -Value $json -Encoding UTF8
    return $path
}

function Complete-InstallLog {
    param(
        [Parameter(Mandatory)]$Session,
        [string]$Status = "success"
    )
    Stop-InstallTranscript -Session $Session
    $footer = "`r`n=== COMPLETE status=$Status at $(Get-Date).ToUniversalTime().ToString('o') ===`r`n"
    Add-Content -LiteralPath $Session.log_file -Value $footer -Encoding UTF8
    Copy-Item -LiteralPath $Session.log_file -Destination $Session.latest_log -Force -ErrorAction SilentlyContinue
    Write-InstallWatchMarker -Session $Session -Status $Status | Out-Null
    Write-Host "[install-log] complete -> $($Session.log_file)" -ForegroundColor Green
}

function Report-InstallFailure {
    param(
        [Parameter(Mandatory)]$Session,
        $ErrorRecord,
        [switch]$SkipGitHubIssue,
        [switch]$OpenBrowser
    )
    Stop-InstallTranscript -Session $Session
    $tail = Get-InstallLogTail -LogFile $Session.log_file
    $body = New-InstallFailureBody -Session $Session -ErrorRecord $ErrorRecord -LogTail $tail
    $title = "Install failed: v$($Session.version) on $($Session.machine.hostname) ($($Session.component))"

    $issue = $null
    if (-not $SkipGitHubIssue) {
        $issue = New-InstallGitHubIssue -Session $Session -Title $title -Body $body
        if ($OpenBrowser -and $issue -and $issue.url -and -not $issue.via_gh) {
            try { Start-Process $issue.url | Out-Null } catch { }
        }
    }

    $footer = "`r`n=== FAILED at $(Get-Date).ToUniversalTime().ToString('o') ===`r`n"
    Add-Content -LiteralPath $Session.log_file -Value $footer -Encoding UTF8
    Copy-Item -LiteralPath $Session.log_file -Destination $Session.latest_log -Force -ErrorAction SilentlyContinue

    $marker = Write-InstallWatchMarker -Session $Session -Status "failed" -ErrorRecord $ErrorRecord -Issue $issue

    Write-Host ""
    Write-Host "INSTALL FAILED" -ForegroundColor Red
    Write-Host "  Log:    $($Session.log_file)" -ForegroundColor Yellow
    Write-Host "  Marker: $marker" -ForegroundColor Yellow
    if ($issue -and $issue.url) {
        Write-Host "  Issue:  $($issue.url)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Melde auch: INSTALL_BLOCKER lonov (Fehlertext aus Log)" -ForegroundColor DarkYellow
}