# register_agent.ps1
# Add a new agent to agents/registry.json, create inbox, brief the operator.
# Windows Terminal agents: prompts for tab_index (1-9) unless -TabIndex is passed.

param(
    [Parameter(Mandatory)]
    [string]$AgentName,

    [Parameter(Mandatory)]
    [string]$DisplayName,

    [Parameter(Mandatory)]
    [string]$ProcessName,

    [Parameter(Mandatory)]
    [string]$WindowTitlePattern,

    [string]$PokeTemplate = "check {inbox_path} and continue",

    [ValidateRange(0, 9)]
    [int]$TabIndex = 0,

    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

function Get-RegistryTabAssignments {
    param($Registry)
    $assignments = @{}
    $Registry.PSObject.Properties | ForEach-Object {
        $entry = $_.Value
        if ($null -ne $entry.tab_index -and [int]$entry.tab_index -ge 1) {
            $assignments[[int]$entry.tab_index] = $_.Name
        }
    }
    return $assignments
}

function Resolve-TabIndex {
    param(
        [string]$Slug,
        [string]$ProcessName,
        [int]$TabIndex,
        $Registry,
        [switch]$NonInteractive
    )
    if ($TabIndex -ge 1) { return $TabIndex }
    if ($ProcessName -ne "WindowsTerminal") { return 0 }

    Write-Host ""
    Write-Host "=== Windows Terminal: tab_index ===" -ForegroundColor Cyan
    Write-Host "Poke springt per Ctrl+Alt+N direkt zum Tab (1 = links, 2 = naechster, ...)."
    $used = Get-RegistryTabAssignments -Registry $Registry
    if ($used.Count -gt 0) {
        Write-Host "Bereits vergeben:" -ForegroundColor DarkGray
        foreach ($key in ($used.Keys | Sort-Object)) {
            Write-Host "  Tab $key -> $($used[$key])"
        }
    } else {
        Write-Host "Noch keine tab_index vergeben." -ForegroundColor DarkGray
    }

    if ($NonInteractive) {
        throw "WindowsTerminal agent '$Slug' needs -TabIndex (1-9). NonInteractive set."
    }

    do {
        $raw = Read-Host "Tab-Nummer fuer '$Slug' (1-9, Enter=ueberspringen)"
        if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }
        if ($raw -match '^[1-9]$') {
            $picked = [int]$raw
            if ($used.ContainsKey($picked) -and $used[$picked] -ne $Slug) {
                Write-Host "Tab $picked ist schon $($used[$picked]). Andere Nummer waehlen." -ForegroundColor Yellow
                continue
            }
            return $picked
        }
        Write-Host "Bitte eine Zahl von 1 bis 9 eingeben." -ForegroundColor Yellow
    } while ($true)
}

$slug = $AgentName.ToLower()
if ($slug -notmatch '^[a-z][a-z0-9_-]{0,31}$') {
    throw "Invalid agent id: $AgentName"
}

$root = Get-Bot2BotRoot
$registryPath = Join-Path $root "agents\registry.json"
$registry = Get-AgentRegistry -Root $root

if ($registry.$slug) {
    throw "Agent '$slug' already exists in registry."
}

$TabIndex = Resolve-TabIndex -Slug $slug -ProcessName $ProcessName -TabIndex $TabIndex -Registry $registry -NonInteractive:$NonInteractive

$entry = [ordered]@{
    display_name         = $DisplayName
    process_name         = $ProcessName
    window_title_pattern = $WindowTitlePattern
    poke_template        = $PokeTemplate
}
if ($TabIndex -ge 1) {
    $entry.tab_index = $TabIndex
}

# ConvertTo-Json on PSCustomObject from registry + new entry
$hash = @{}
$registry.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
$hash[$slug] = $entry
$hash | ConvertTo-Json -Depth 5 | Set-Content -Path $registryPath -Encoding UTF8

$inbox = Get-InboxPath -AgentName $slug -Root $root
if (-not (Test-Path $inbox)) {
    Set-Content -Path $inbox -Value "# inbox for $slug (no messages yet)`n" -Encoding UTF8
}

Write-Bot2BotLog -Component "register_agent" -Message "Registered agent $slug tab_index=$TabIndex"
Write-Host "[register_agent] Registered '$slug' -> $registryPath" -ForegroundColor Green
Write-Host "[register_agent] Inbox: $inbox" -ForegroundColor DarkGray

Write-Host ""
Write-Host "=== Agent briefing: $slug ===" -ForegroundColor Cyan
Write-Host "  inbox:     bot2bot/inbox/$slug.txt"
Write-Host "  history:   bot2bot/history/conversation.jsonl (append-only)"
Write-Host "  send:      .\append_message.ps1 -From <you> -To $slug -Subject ... -Body ... -Status info"
if ($ProcessName -eq "WindowsTerminal" -and $TabIndex -ge 1) {
    Write-Host "  tab_index: $TabIndex  (poke: Ctrl+Alt+$TabIndex)"
    Write-Host "  title:     Tab-Titel soll '$slug' erkennbar machen (z.B. '^$slug' oder ' - $slug')"
}
if ($ProcessName -eq "WindowsTerminal") {
    Write-Host "  poke:      .\poke.ps1 -To $slug  (von anderem WT-Tab: -Async)"
}
Write-Host "  poke+msg:  .\append_message.ps1 ... -To $slug -Poke"
Write-Host "  template:  $PokeTemplate"