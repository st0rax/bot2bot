# ensure_prerequisites.ps1 - Python 3.11+ und pwsh 7 (user-level, kein UAC)
#
# Policy: Keine winget/machine-scope-Installs (UAC-Risiko).
# Falls ein Dialog noetig ist: Audio-Aufforderung an Storax + Warteschleife (kein Timeout-Stille).

param()

$ErrorActionPreference = "Stop"

$script:MinPythonMajor = 3
$script:MinPythonMinor = 11
$script:PreferredPythonVersion = "3.13.5"
$script:PwshPortableVersion = "7.5.2"
$script:UserActionTimeoutSec = 600
$script:UserActionRemindSec = 45

function Refresh-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Test-IsWindowsAppsStub {
    param([string]$Path)
    return $Path -match '\\WindowsApps\\'
}

function Test-IsProcessElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-InstallAudioPrompt {
    param([string]$Message)

    $common = ""
    if ($PSScriptRoot) { $common = Join-Path $PSScriptRoot "bot2bot_common.ps1" }
    if ($common -and (Test-Path -LiteralPath $common)) {
        . $common
        Invoke-HumanAttentionAudio -Message $Message
        return
    }

    try {
        [System.Media.SystemSounds]::Exclamation.Play() | Out-Null
        Start-Sleep -Milliseconds 300
        [System.Media.SystemSounds]::Exclamation.Play() | Out-Null
    } catch {
        try {
            [Console]::Beep(880, 180)
            [Console]::Beep(1100, 180)
        } catch { }
    }

    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.Rate = 0
        $synth.Speak($Message)
        $synth.Dispose()
    } catch {
        Write-Host "[audio] $Message" -ForegroundColor Yellow
    }
}

function Wait-ForUserInstallStep {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][scriptblock]$Poll,
        [int]$TimeoutSec = $script:UserActionTimeoutSec,
        [int]$RemindSec = $script:UserActionRemindSec
    )

    Write-Host "[prereq] $Prompt" -ForegroundColor Cyan
    Invoke-InstallAudioPrompt -Message $Prompt

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $lastRemind = (Get-Date).AddSeconds(-$RemindSec)

    while ((Get-Date) -lt $deadline) {
        $state = & $Poll
        switch ($state) {
            "done" { return $true }
            "fail" { return $false }
        }
        if (((Get-Date) - $lastRemind).TotalSeconds -ge $RemindSec) {
            $remind = "Storax, bitte den Installationsdialog bestaetigen. $Prompt"
            Write-Host "[prereq] $remind" -ForegroundColor Yellow
            Invoke-InstallAudioPrompt -Message $remind
            $lastRemind = Get-Date
        }
        Start-Sleep -Seconds 2
    }

    Invoke-InstallAudioPrompt -Message "Zeitueberschreitung beim Installieren. Bitte manuell pruefen."
    return $false
}

function Get-PythonInfo {
    param([Parameter(Mandatory)][string]$Exe)

    if (-not (Test-Path $Exe)) { return $null }
    if (Test-IsWindowsAppsStub -Path $Exe) { return $null }

    try {
        $ver = & $Exe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        $parts = $ver.ToString().Trim().Split(".")
        $major = [int]$parts[0]
        $minor = [int]$parts[1]
        if ($major -gt $script:MinPythonMajor -or ($major -eq $script:MinPythonMajor -and $minor -ge $script:MinPythonMinor)) {
            return [pscustomobject]@{
                Exe     = $Exe
                Version = $ver.ToString().Trim()
                Major   = $major
                Minor   = $minor
            }
        }
    } catch { }

    return $null
}

function Find-CompatiblePython {
    $candidates = [System.Collections.Generic.List[string]]::new()

    if (Get-Command py -ErrorAction SilentlyContinue) {
        foreach ($tag in @("3.13", "3.12", "3.11")) {
            try {
                $resolved = & py "-$tag" -c "import sys; print(sys.executable)" 2>&1
                if ($LASTEXITCODE -eq 0 -and $resolved) {
                    $candidates.Add($resolved.ToString().Trim())
                }
            } catch { }
        }
    }

    $roots = @($env:LOCALAPPDATA) | Where-Object { $_ }
    foreach ($root in $roots) {
        foreach ($pattern in @("Python\Python3*\python.exe", "Programs\Python\Python3*\python.exe")) {
            $glob = Join-Path $root $pattern
            Get-ChildItem -Path $glob -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$candidates.Add($_.FullName)
            }
        }
    }

    foreach ($name in @("python3.13", "python3.12", "python3.11", "python3", "python")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $candidates.Add($cmd.Source) }
    }

    $seen = @{}
    $best = $null
    foreach ($exe in $candidates) {
        if (-not $exe -or $seen.ContainsKey($exe)) { continue }
        $seen[$exe] = $true
        $info = Get-PythonInfo -Exe $exe
        if (-not $info) { continue }
        if (-not $best -or $info.Major -gt $best.Major -or ($info.Major -eq $best.Major -and $info.Minor -gt $best.Minor)) {
            $best = $info
        }
    }
    return $best
}

function Install-PythonUser {
    param([switch]$NonInteractive)

    Write-Host "[prereq] Python $($script:MinPythonMajor).$($script:MinPythonMinor)+ - user-level install (no UAC)" -ForegroundColor Yellow

    $ver = $script:PreferredPythonVersion
    $installer = Join-Path $env:TEMP "python-$ver-amd64.exe"
    $url = "https://www.python.org/ftp/python/$ver/python-$ver-amd64.exe"
    Write-Host "[prereq] Download: $url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

    # InstallAllUsers=0 => nur Benutzerprofil, typischerweise kein UAC
    $installArgs = @(
        "/passive", "InstallAllUsers=0", "PrependPath=1",
        "Include_launcher=1", "Include_test=0", "AssociateFiles=0",
        "Shortcuts=0"
    )

    $prompt = "Storax, Python wird installiert. Falls ein Sicherheitsdialog erscheint, bitte auf Ja klicken."
    if (-not $NonInteractive) {
        $answer = Read-Host "Python $ver jetzt installieren? [J/n]"
        if ($answer -match '^[Nn]') { throw "Python-Installation abgebrochen." }
    }

    $proc = Start-Process -FilePath $installer -ArgumentList $installArgs -PassThru
    $ok = Wait-ForUserInstallStep -Prompt $prompt -Poll {
        if (-not $proc.HasExited) { return "pending" }
        if ($proc.ExitCode -eq 0) { return "done" }
        return "fail"
    }
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
    if (-not $ok) { throw "Python-Installer exit $($proc.ExitCode) oder Timeout" }

    Refresh-SessionPath
    Start-Sleep -Seconds 2

    $found = Find-CompatiblePython
    if (-not $found) {
        $hint = Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe"
        if (Test-Path $hint) { $found = Get-PythonInfo -Exe $hint }
    }
    if (-not $found) {
        throw "Python installiert, aber nicht auffindbar. Terminal neu starten und Installer erneut ausfuehren."
    }
    Write-Host "[prereq] Python $($found.Version) ($($found.Exe))" -ForegroundColor Green
    return $found
}

function Install-Pwsh7User {
    param([switch]$NonInteractive)

    $dest = Join-Path $env:LOCALAPPDATA "Programs\PowerShell\7"
    $pwsh = Join-Path $dest "pwsh.exe"
    if (Test-Path $pwsh) { return $pwsh }

    Write-Host "[prereq] pwsh 7 - portable user-level install (no UAC)" -ForegroundColor Yellow
    $ver = $script:PwshPortableVersion
    $zipUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$ver/PowerShell-$ver-win-x64.zip"
    $zipPath = Join-Path $env:TEMP "PowerShell-$ver-win-x64.zip"

    Write-Host "[prereq] Download: $zipUrl" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $dest -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $pwsh)) { throw "Portable pwsh nicht gefunden: $pwsh" }

    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$dest*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$dest;$userPath", "User")
        Refresh-SessionPath
    }

    Write-Host "[prereq] pwsh portable: $pwsh" -ForegroundColor Green
    return $pwsh
}

function Resolve-Pwsh7 {
    $candidates = @(
        (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        (Join-Path $env:LOCALAPPDATA "Programs\PowerShell\7\pwsh.exe"),
        "${env:ProgramFiles}\PowerShell\7\pwsh.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    return $candidates | Select-Object -First 1
}

function Ensure-Pwsh7 {
    param(
        [string]$ScriptUrl = "",
        [hashtable]$BoundParams = @{},
        [switch]$NonInteractive
    )

    if ($PSVersionTable.PSVersion.Major -ge 7) { return $null }

    Write-Host "[prereq] Windows PowerShell $($PSVersionTable.PSVersion) - switching to pwsh 7" -ForegroundColor Yellow
    $pwshPath = Resolve-Pwsh7
    if (-not $pwshPath) {
        $pwshPath = Install-Pwsh7User -NonInteractive:$NonInteractive
    }

    $scriptFile = $PSCommandPath
    if (-not $scriptFile -and $ScriptUrl) {
        $scriptFile = Join-Path $env:TEMP "install-webagent.ps1"
        Write-Host "[prereq] Lade Installer: $ScriptUrl" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $ScriptUrl -OutFile $scriptFile -UseBasicParsing
    }
    if (-not $scriptFile -or -not (Test-Path $scriptFile)) {
        throw "Kein Installer-Pfad. Nutze: irm <url>/install-webagent.ps1 | iex"
    }

    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptFile)
    foreach ($key in $BoundParams.Keys) {
        $val = $BoundParams[$key]
        if ($val -is [switch]) {
            if ($val) { $argList += "-$key" }
        } elseif ($null -ne $val -and "$val" -ne "") {
            $argList += "-$key"
            $argList += "$val"
        }
    }
    & $pwshPath @argList
    exit $LASTEXITCODE
}

function Ensure-InstallPrerequisites {
    param(
        [switch]$NonInteractive,
        [string]$PythonExe = ""
    )

    if (Test-IsProcessElevated) {
        Write-Host "[prereq] Hint: running as Admin - still prefer user-level installs." -ForegroundColor Yellow
    }

    if ($PythonExe) {
        $info = Get-PythonInfo -Exe $PythonExe
        if ($info) { return $info }
        Write-Host "[prereq] Angegebenes Python ungeeignet: $PythonExe" -ForegroundColor Yellow
    }

    $found = Find-CompatiblePython
    if ($found) {
        Write-Host "[prereq] Python $($found.Version) ($($found.Exe))" -ForegroundColor Green
        return $found
    }

    return Install-PythonUser -NonInteractive:$NonInteractive
}