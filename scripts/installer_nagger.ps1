# installer_nagger.ps1 - WebAgent Nagger: Installer + Anti-Pause
#
# 1) lonov-Install ueberwachen bis INSTALL_OK
# 2) ALLE aktiven WebBrains gegen Pause: Repoke bei Stille, Keepalive-Nudge
#
# Dauerbetrieb:
#   Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','...\installer_nagger.ps1','-Force' -WindowStyle Hidden

param(
    [string]$Version = "0.1.9",
    [string[]]$NaggerAgents = @(),
    [string]$Repo = "alexanderkrenz89-ctrl/webagent",
    [int]$PollSeconds = 30,
    [int]$RepokeSeconds = 90,
    [int]$IdleSeconds = 300,
    [int]$EscalateAfterNags = 3,
    [switch]$Once,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$InstallOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot

if (-not $NaggerAgents -or $NaggerAgents.Count -eq 0) {
    $pickScript = Join-Path $PSScriptRoot "pick_nagger_agent.ps1"
    $pick = (& $pickScript -Root $root | Out-String) | ConvertFrom-Json
    $NaggerAgents = @($pick.primary) + @($pick.backups)
    $scoreLine = ($pick.ranked | ForEach-Object { "$($_.agent)=$($_.score)" }) -join ', '
    Write-Host "[nagger] auto-pick: primary=$($pick.primary) backups=$($pick.backups -join ',') scores=$scoreLine" -ForegroundColor Green
}

$watchDir = Join-Path $root "data\watch"
$okFile = Join-Path $watchDir "installer_lonov_ok.json"
$lockFile = Join-Path $watchDir "_installer_nagger.lock"
$stateFile = Join-Path $watchDir "_installer_nagger_state.json"
$appendScript = Join-Path $PSScriptRoot "append_message.ps1"
$pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
$baseUrl = "https://github.com/$Repo/releases/download/v$Version"

if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Path $watchDir -Force | Out-Null }

if ((Test-Path $lockFile) -and -not $Force -and -not $Once) {
    $existing = Get-Content $lockFile -Raw | ConvertFrom-Json
    if ($existing.pid -and (Get-Process -Id $existing.pid -ErrorAction SilentlyContinue)) {
        Write-Host "[nagger] Already running pid=$($existing.pid). Use -Force." -ForegroundColor Yellow
        exit 1
    }
}
if (-not $Once) {
    @{ pid = $PID; started = (Get-Date).ToUniversalTime().ToString("o"); version = $Version } |
        ConvertTo-Json | Set-Content -Path $lockFile -Encoding UTF8
}

function New-DefaultState {
    return [pscustomobject]@{
        nag_count        = 0
        repoke_count     = 0
        keepalive_count  = 0
        last_nag         = ""
        last_message_id  = ""
        agent_index      = 0
        escalated        = $false
        blocker_seen     = $false
        failure_seen     = $false
        install_done     = $false
        agent_repokes    = [pscustomobject]@{}
        agent_keepalives = [pscustomobject]@{}
        last_cycle       = ""
    }
}

function Get-NagState {
    if (-not (Test-Path $stateFile)) { return New-DefaultState }
    $s = Get-Content $stateFile -Raw | ConvertFrom-Json
    foreach ($pair in @(
        @{ Name = "nag_count"; Value = 0 },
        @{ Name = "repoke_count"; Value = 0 },
        @{ Name = "keepalive_count"; Value = 0 },
        @{ Name = "agent_index"; Value = 0 },
        @{ Name = "last_nag"; Value = "" },
        @{ Name = "last_message_id"; Value = "" },
        @{ Name = "last_cycle"; Value = "" },
        @{ Name = "escalated"; Value = $false },
        @{ Name = "install_done"; Value = $false }
    )) {
        if ($null -eq $s.PSObject.Properties[$pair.Name]) {
            $s | Add-Member -NotePropertyName $pair.Name -NotePropertyValue $pair.Value -Force
        }
    }
    if ($null -eq $s.PSObject.Properties["agent_repokes"]) {
        $s | Add-Member -NotePropertyName agent_repokes -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.PSObject.Properties["agent_keepalives"]) {
        $s | Add-Member -NotePropertyName agent_keepalives -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    return $s
}

function Save-NagState { param($State); $State | ConvertTo-Json -Depth 8 | Set-Content -Path $stateFile -Encoding UTF8 }

function Get-PropOrDefault { param($Obj, [string]$Name, $Default = 0)
    if ($null -eq $Obj) { return $Default }
    $v = $Obj.PSObject.Properties[$Name]
    if ($null -eq $v) { return $Default }
    return $v.Value
}

function Get-RecentMessages {
    $historyPath = Get-HistoryPath -Root $root
    if (-not (Test-Path $historyPath)) { return @() }
    return @(Get-Content $historyPath -Tail 400 -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ })
}

function Get-ActiveWebBrains {
    $list = [System.Collections.Generic.List[string]]::new()
    $registry = Get-AgentRegistry -Root $root
    foreach ($prop in $registry.PSObject.Properties) {
        $cfg = Get-AgentConfig -AgentName $prop.Name -Root $root
        if ($cfg.Active -and $cfg.Kind -eq "webbrain") { [void]$list.Add($cfg.Name) }
    }
    return @($list)
}

function Test-InstallConfirmed {
    if (Test-Path -LiteralPath $okFile) { return $true }
    $msgs = Get-RecentMessages
    return [bool]($msgs | Where-Object { $_.subject -match 'INSTALL_OK\s+lonov' } | Select-Object -First 1)
}

function Get-InstallBlocker {
    $msgs = Get-RecentMessages
    return $msgs | Where-Object { $_.subject -match 'INSTALL_BLOCKER\s+lonov' } | Select-Object -First 1
}

function Get-InstallFailureMarker {
    $latest = Join-Path $watchDir "install_latest.json"
    if (-not (Test-Path -LiteralPath $latest)) { return $null }
    try {
        $m = Get-Content -LiteralPath $latest -Raw | ConvertFrom-Json
        if ($m.status -eq "failed") { return $m }
    } catch { }
    return $null
}

function Test-LiveAsset {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
        return ($r.StatusCode -eq 200 -and $r.Content.Length -gt 500)
    } catch { return $false }
}

function Invoke-PokeAgent {
    param([string]$Agent, [string]$Reason)
    Write-Host "[nagger] POKE $Agent ($Reason)" -ForegroundColor Yellow
    if ($DryRun) { return }
    try { & $pokeScript -AgentName $Agent 2>&1 | Out-Null } catch {
        Write-Host "[nagger] poke $Agent failed: $_" -ForegroundColor DarkYellow
    }
}

function Get-AgentActivity {
    param([string]$Agent, $Messages)
    $inLast = $Messages | Where-Object { $_.to -eq $Agent } | Select-Object -Last 1
    $outLast = $Messages | Where-Object { $_.from -eq $Agent } | Select-Object -Last 1
    $pending = $false
    $pendingAgeSec = 0
    $idleSec = [int]::MaxValue

    if ($inLast) {
        $inTs = [datetime]::Parse($inLast.ts).ToUniversalTime()
        $outTs = if ($outLast) { [datetime]::Parse($outLast.ts).ToUniversalTime() } else { [datetime]::MinValue }
        if ($outTs -lt $inTs) {
            $pending = $true
            $pendingAgeSec = [int](((Get-Date).ToUniversalTime() - $inTs).TotalSeconds)
        }
    }
    $lastAct = if ($outLast -and $inLast) {
        $a = [datetime]::Parse($outLast.ts).ToUniversalTime()
        $b = [datetime]::Parse($inLast.ts).ToUniversalTime()
        if ($a -gt $b) { $a } else { $b }
    } elseif ($outLast) { [datetime]::Parse($outLast.ts).ToUniversalTime() }
      elseif ($inLast) { [datetime]::Parse($inLast.ts).ToUniversalTime() }
      else { $null }
    if ($lastAct) { $idleSec = [int](((Get-Date).ToUniversalTime() - $lastAct).TotalSeconds) }

    return [pscustomobject]@{
        Agent         = $Agent
        Pending       = $pending
        PendingAgeSec = $pendingAgeSec
        IdleSec       = $idleSec
        InSubject     = if ($inLast) { $inLast.subject } else { "" }
        InMsgId       = if ($inLast) { $inLast.id } else { "" }
    }
}

function Send-KeepaliveNudge {
    param([string]$Agent, [string]$MissionLine)
    $body = @"
KEINE PAUSE - sofort weiterarbeiten

Agent: $Agent
Regel: Keine Leerlaufzeit. Inbox lesen, antworten, nicht warten.

$MissionLine

Pflicht:
  1. inbox/$Agent.txt lesen
  2. Offene Fragen beantworten ODER BLOCKER an grok melden
  3. Kein "warte auf X" ohne parallele Aktion

Antwort-Format bei Fortschritt: STATUS <agent> <1 Zeile>
"@
    if ($DryRun) { Write-Host "[nagger] KEEPALIVE -> $Agent"; return }
    $tmp = Join-Path $env:TEMP "nag_keepalive_$Agent.txt"
    Set-Content -Path $tmp -Value $body -Encoding UTF8
    & $appendScript -From grok -To $Agent -Subject "KEINE PAUSE $Agent" -BodyPath $tmp -Status question | Out-Null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

function Invoke-AntiPause {
    param($State)
    $msgs = Get-RecentMessages
    $brains = Get-ActiveWebBrains
    if (-not $brains.Count) { return $State }

    $mission = if ($State.install_done) {
        "Mission: allgemeine bot2bot-Aufgaben (Installer erledigt)."
    } else {
        "Mission PRIORITAET: lonov Installer v$Version bis INSTALL_OK lonov."
    }

    foreach ($agent in $brains) {
        $act = Get-AgentActivity -Agent $agent -Messages $msgs

        if ($act.Pending -and $act.PendingAgeSec -ge $RepokeSeconds) {
            $key = "$agent`:$($act.InMsgId)"
            $rc = [int](Get-PropOrDefault -Obj $State.agent_repokes -Name $key -Default 0)
            $State.repoke_count++
            $State.agent_repokes | Add-Member -NotePropertyName $key -NotePropertyValue ($rc + 1) -Force
            Invoke-PokeAgent -Agent $agent -Reason "unanswered ${act.PendingAgeSec}s '$($act.InSubject)'"
            continue
        }

        if (-not $act.Pending -and $act.IdleSec -ge $IdleSeconds) {
            $lastKa = Get-PropOrDefault -Obj $State.agent_keepalives -Name $agent -Default ""
            $kaOk = $true
            if ($lastKa) {
                $kaOk = (((Get-Date).ToUniversalTime() - [datetime]::Parse($lastKa).ToUniversalTime()).TotalSeconds -ge $IdleSeconds)
            }
            if ($kaOk) {
                $State.keepalive_count++
                $State.agent_keepalives | Add-Member -NotePropertyName $agent -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o")) -Force
                Send-KeepaliveNudge -Agent $agent -MissionLine $mission
                Invoke-PokeAgent -Agent $agent -Reason "idle ${act.IdleSec}s"
            }
        }
    }
    return $State
}

function Send-InstallNag {
    param([string]$Agent, [int]$NagNum, [switch]$Escalate)
    $installUrl = "$baseUrl/install-webagent.ps1"
    $live = Test-LiveAsset $installUrl
    $body = @"
INSTALL NAG #$NagNum - lonov v$Version

Live: $(if ($live) { 'OK' } else { 'FEHLT' }) $installUrl

lonov:
  cd <Zielordner>
  irm $installUrl | iex
  cd .\bot2bot\scripts; .\oobe_wizard.ps1

Melde grok: INSTALL_OK lonov oder INSTALL_BLOCKER lonov
"@
    if ($DryRun) { return "" }
    $tmp = Join-Path $env:TEMP "installer_nag_$NagNum.txt"
    Set-Content -Path $tmp -Value $body -Encoding UTF8
    & $appendScript -From grok -To $Agent -Subject "NAG lonov v$Version #$NagNum" -BodyPath $tmp -Status question -HumanAttention:$Escalate.IsPresent | Out-Null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $msgs = Get-RecentMessages
    $last = $msgs | Where-Object { $_.to -eq $Agent -and $_.subject -match "NAG lonov" } | Select-Object -Last 1
    if ($last) { return $last.id }
    return ""
}

function Invoke-InstallNag {
    param($State)
    if ($State.install_done) { return $State }

    $blocker = Get-InstallBlocker
    if ($blocker -and -not $State.blocker_seen) {
        $State.blocker_seen = $true
        Write-Host "[nagger] INSTALL_BLOCKER lonov: $($blocker.subject)" -ForegroundColor Red
        if (-not $DryRun) {
            $body = "INSTALL_BLOCKER lonov erkannt.`n`nSubject: $($blocker.subject)`n`n$($blocker.body)"
            $tmp = Join-Path $env:TEMP "installer_blocker_alert.txt"
            Set-Content -Path $tmp -Value $body -Encoding UTF8
            & $appendScript -From grok -To storax -Subject "BLOCKER lonov v$Version" -BodyPath $tmp -Status question -HumanAttention | Out-Null
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    $failMarker = Get-InstallFailureMarker
    if ($failMarker -and -not $State.failure_seen) {
        $State.failure_seen = $true
        Write-Host "[nagger] install log failure: $($failMarker.log_file)" -ForegroundColor Red
        if ($failMarker.issue_url) {
            Write-Host "[nagger] issue: $($failMarker.issue_url)" -ForegroundColor Yellow
        }
    }

    if (Test-InstallConfirmed) {
        Write-Host "[nagger] INSTALL_OK lonov" -ForegroundColor Green
        $State.install_done = $true
        return $State
    }

    $agents = @()
    foreach ($name in $NaggerAgents) {
        $cfg = Get-AgentConfig -AgentName $name -Root $root
        if ($cfg.Active -and $cfg.Kind -eq "webbrain") { $agents += $name }
    }
    if (-not $agents.Count) { return $State }

    $agent = $agents[$State.agent_index % $agents.Count]
    $since = if ($State.last_nag) {
        [int](((Get-Date).ToUniversalTime() - [datetime]::Parse($State.last_nag).ToUniversalTime()).TotalSeconds)
    } else { [int]::MaxValue }

    $escalate = ($State.nag_count -ge $EscalateAfterNags) -and -not $State.escalated
    if ($since -ge $RepokeSeconds -or -not $State.last_message_id -or $escalate) {
        $State.nag_count++
        if ($escalate) { $State.escalated = $true }
        Write-Host "[nagger] INSTALL NAG #$($State.nag_count) -> $agent" -ForegroundColor Cyan
        $State.last_message_id = Send-InstallNag -Agent $agent -NagNum $State.nag_count -Escalate:$escalate
        $State.last_nag = (Get-Date).ToUniversalTime().ToString("o")
        Invoke-PokeAgent -Agent $agent -Reason "install-nag"
        if ($escalate) {
            foreach ($b in $agents | Where-Object { $_ -ne $agent }) {
                Invoke-PokeAgent -Agent $b -Reason "install-escalate"
            }
        }
        $State.agent_index = ($State.agent_index + 1) % $agents.Count
    }
    return $State
}

function Invoke-NagCycle {
    param($State)
    $State.last_cycle = (Get-Date).ToUniversalTime().ToString("o")

    if (-not $InstallOnly) {
        $State = Invoke-AntiPause -State $State
    }
    $State = Invoke-InstallNag -State $State

    Save-NagState $State
    return $State
}

$swarmScript = Join-Path $PSScriptRoot "installer_swarm.ps1"
$swarmMarker = Join-Path $watchDir "installer_swarm.json"
if ((Test-Path $swarmScript) -and -not (Test-Path $swarmMarker) -and -not $DryRun) {
    Write-Host "[nagger] initial swarm mobilize ..." -ForegroundColor Cyan
    & $swarmScript -Version $Version | Out-Null
}

Write-Host "[nagger] poll=${PollSeconds}s repoke=${RepokeSeconds}s idle=${IdleSeconds}s install=v$Version" -ForegroundColor Cyan
Write-Host "[nagger] modus: installer + anti-pause (alle WebBrains)" -ForegroundColor Cyan

$state = Get-NagState
do {
    $state = Invoke-NagCycle -State $state
    if ($Once) { break }
    Write-Host "[nagger] cycle done repokes=$($state.repoke_count) keepalives=$($state.keepalive_count) install_nags=$($state.nag_count) install_done=$($state.install_done)" -ForegroundColor DarkGray
    Start-Sleep -Seconds $PollSeconds
    $state = Get-NagState
} while ($true)

if (-not $Once -and (Test-Path $lockFile)) {
    $cur = Get-Content $lockFile -Raw | ConvertFrom-Json
    if ($cur.pid -eq $PID) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
}
exit 0