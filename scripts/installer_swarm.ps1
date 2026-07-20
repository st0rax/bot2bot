# installer_swarm.ps1 - Alle freien WebBrains fuer lonov-Installer mobilisieren
#
#   .\installer_swarm.ps1
#   .\installer_swarm.ps1 -PokeOnly   # nur poken, keine neuen Messages

param(
    [string]$Version = "0.1.10",
    [string]$Repo = "st0rax/webagent",
    [switch]$PokeOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$watchDir = Join-Path $root "data\watch"
$swarmFile = Join-Path $watchDir "installer_swarm.json"
$appendScript = Join-Path $PSScriptRoot "append_message.ps1"
$pokeScript = Join-Path $PSScriptRoot "poke_agent.ps1"
$installUrl = "https://github.com/$Repo/releases/download/v$Version/install-webagent.ps1"

if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Path $watchDir -Force | Out-Null }

function Set-EntryActive {
    param($Entry, [bool]$Value)
    if ($null -eq $Entry) { return }
    $Entry | Add-Member -NotePropertyName active -NotePropertyValue $Value -Force
}

function Enable-AllWebBrains {
    $regPath = Join-Path $root "agents\registry.json"
    $registry = Get-Content $regPath -Raw | ConvertFrom-Json
    $activated = @()
    foreach ($prop in $registry.PSObject.Properties) {
        if ($prop.Value.kind -ne "webbrain") { continue }
        if (-not $prop.Value.active) {
            Set-EntryActive -Entry $prop.Value -Value $true
            $activated += $prop.Name
        }
    }
    if ($activated.Count -and -not $DryRun) {
        $registry | ConvertTo-Json -Depth 6 | Set-Content $regPath -Encoding UTF8
    }
    return $activated
}

function Get-RecentMessages {
    $hp = Get-HistoryPath -Root $root
    if (-not (Test-Path $hp)) { return @() }
    return @(Get-Content $hp -Tail 400 | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ })
}

function Test-AgentBusy {
    param([string]$Agent, $Messages)
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-2)
    $recent = @($Messages | Where-Object {
        ($_.from -eq $Agent -or $_.to -eq $Agent) -and [datetime]::Parse($_.ts).ToUniversalTime() -ge $cutoff
    })
    $openTo = $recent | Where-Object { $_.to -eq $Agent } | Select-Object -Last 1
    if (-not $openTo) { return $false }
    $inTs = [datetime]::Parse($openTo.ts).ToUniversalTime()
    $replied = $recent | Where-Object {
        $_.from -eq $Agent -and [datetime]::Parse($_.ts).ToUniversalTime() -ge $inTs -and
        $_.subject -notmatch '^(NAG|KEINE PAUSE|INSTALL SWARM)'
    } | Select-Object -First 1
    return (-not $replied)
}

$roles = [ordered]@{
    chatgpt  = "ROLLE: PS5.1 iex-Bootstrap + Koordination. Pruefe: irm|iex Pfad, ensure_prerequisites Cache, pwsh-Handoff."
    kimi     = "ROLLE: OOBE + first_login_wizard. Pruefe: eine Brain-Auswahl, Login optional, PS5.1 Add-Member."
    gemini   = "ROLLE: ZIP/INSTALL.ps1. Pruefe: InstallRoot=pwd, ForceCopy, scripts /IS /IT, registry.release.json."
    deepseek = "ROLLE: verify_install.ps1. Pruefe: ohne Login gruen, -Strict nach OOBE, grok-skip wenn nicht in registry."
    qwen     = "ROLLE: ensure_prerequisites. Pruefe: Python 3.11+ user-install, pwsh portable, kein UAC, Dialog-Warte."
    mistral  = "ROLLE: Release-Pipeline. Pruefe: pre_release_verify, git_release Assets, live URL 200."
    claude   = "ROLLE: Blocker-Triage. Liste alle SHOWSTOPPER fuer frischen Windows-10 PC (lonov)."
    zai      = "ROLLE: Zweitmeinung lonov. Simuliere frischen User: cd Zielordner, irm|iex - was kann schiefgehen?"
}

Write-Host "=== installer_swarm v$Version ===" -ForegroundColor Cyan

$activated = Enable-AllWebBrains
if ($activated.Count) {
    Write-Host "[swarm] aktiviert: $($activated -join ', ')" -ForegroundColor Green
}

$msgs = Get-RecentMessages
$dispatched = [System.Collections.Generic.List[object]]::new()

foreach ($agent in $roles.Keys) {
    $cfg = Get-AgentConfig -AgentName $agent -Root $root
    if ($cfg.Kind -ne "webbrain") { continue }

    $busy = Test-AgentBusy -Agent $agent -Messages $msgs
    $status = if ($busy) { "busy-skip" } else { "assigned" }

    if ($busy -and -not $PokeOnly) {
        Write-Host "[swarm] $agent BUSY - nur poke" -ForegroundColor DarkYellow
        $status = "busy-poke"
    }

    if (-not $PokeOnly -and $status -ne "busy-skip") {
        $body = @"
INSTALL SWARM v$Version - SOFORTIGER AUFTRAG (Storax)

$($roles[$agent])

Live:
  irm $installUrl | iex

lonov danach:
  cd .\bot2bot\scripts; .\oobe_wizard.ps1

Antwortformat (an grok):
  INSTALL_REVIEW $agent OK|<BLOCKER text>
  oder INSTALL_BLOCKER lonov <konkret>

Keine Pause. Max 15 Min. Wenn BLOCKER: sofort melden, nicht warten.
"@
        if ($DryRun) {
            Write-Host "[swarm] DRY message -> $agent" -ForegroundColor DarkGray
        } else {
            $tmp = Join-Path $env:TEMP "swarm_$agent.txt"
            Set-Content -Path $tmp -Value $body -Encoding UTF8
            & $appendScript -From grok -To $agent -Subject "INSTALL SWARM v$Version - $($roles[$agent].Split('.')[0])" -BodyPath $tmp -Status question | Out-Null
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-Host "[swarm] message -> $agent" -ForegroundColor Green
        }
    }

    if (-not $DryRun) {
        $spawnArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $pokeScript, "-AgentName", $agent)
        Start-Process -FilePath "pwsh" -ArgumentList $spawnArgs -WorkingDirectory $PSScriptRoot -WindowStyle Hidden | Out-Null
        Write-Host "[swarm] async poke -> $agent" -ForegroundColor Yellow
    } else {
        Write-Host "[swarm] DRY poke -> $agent" -ForegroundColor DarkGray
    }

    [void]$dispatched.Add([pscustomobject]@{ agent = $agent; status = $status; role = $roles[$agent].Split('.')[0] })
}

$swarmState = @{
    version     = $Version
    mobilized_at = (Get-Date).ToUniversalTime().ToString("o")
    install_url = $installUrl
    activated   = $activated
    dispatched  = @($dispatched)
    success     = "INSTALL_OK lonov"
    blocker     = "INSTALL_BLOCKER lonov"
}
if (-not $DryRun) {
    $swarmState | ConvertTo-Json -Depth 5 | Set-Content $swarmFile -Encoding UTF8
}

Write-Host ""
Write-Host "[swarm] $($dispatched.Count) agents mobilized. State: $swarmFile" -ForegroundColor Cyan
Write-Host "[swarm] nagger + anti-pause laeuft parallel (installer_nagger.ps1)" -ForegroundColor DarkGray
exit 0