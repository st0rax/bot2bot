# Shared helpers for bot2bot (agent-agnostic).

function Get-Bot2BotRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-AgentRegistry {
    param([string]$Root = (Get-Bot2BotRoot))
    $path = Join-Path $Root "agents\registry.json"
    if (-not (Test-Path $path)) {
        throw "Agent registry not found: $path"
    }
    return Get-Content $path -Raw | ConvertFrom-Json
}

function Get-AgentConfig {
    param(
        [Parameter(Mandatory)]
        [string]$AgentName,
        [string]$Root = (Get-Bot2BotRoot)
    )
    $slug = $AgentName.ToLower()
    $registry = Get-AgentRegistry -Root $Root
    $config = $registry.$slug
    if (-not $config) {
        throw "Agent '$slug' is not registered. Add an entry to agents/registry.json (see README)."
    }
    $kind = if ($config.kind) { [string]$config.kind } else { "desktop" }
    $brainId = if ($config.brain_id) { [string]$config.brain_id } else { $slug }
    $active = $true
    if ($null -ne $config.active) {
        $active = [bool]$config.active
    }
    $tabIndex = 0
    if ($null -ne $config.tab_index) {
        $tabIndex = [int]$config.tab_index
    }
    return [pscustomobject]@{
        Name                       = $slug
        DisplayName                = $config.display_name
        Kind                       = $kind
        BrainId                    = $brainId
        Active                     = $active
        InactiveReason             = if ($config.inactive_reason) { [string]$config.inactive_reason } else { "" }
        ProcessName                = $config.process_name
        TabIndex                   = $tabIndex
        WindowTitlePattern         = $config.window_title_pattern
        FallbackProcessName        = if ($config.fallback_process_name) { [string]$config.fallback_process_name } else { "" }
        FallbackWindowTitlePattern = if ($config.fallback_window_title_pattern) { [string]$config.fallback_window_title_pattern } else { "" }
        PokeFallback               = if ($config.poke_fallback) { [string]$config.poke_fallback } else { "" }
        PokeTemplate               = $config.poke_template
        PollMode                   = if ($config.poll_mode) { [string]$config.poll_mode } else { "self" }
        BackgroundPoll             = if ($null -ne $config.background_poll) { [bool]$config.background_poll } else { $true }
        WakeCommand                = if ($config.wake_command) { [string]$config.wake_command } else { $null }
    }
}

function Test-AgentIsActive {
    param(
        [Parameter(Mandatory)]
        [string]$AgentName,
        [string]$Root = (Get-Bot2BotRoot)
    )
    $config = Get-AgentConfig -AgentName $AgentName -Root $Root
    return [bool]$config.Active
}

function Get-HistoryPath {
    param([string]$Root = (Get-Bot2BotRoot))
    return Join-Path $Root "history\conversation.jsonl"
}

function Get-InboxPath {
    param(
        [Parameter(Mandatory)]
        [string]$AgentName,
        [string]$Root = (Get-Bot2BotRoot)
    )
    $slug = $AgentName.ToLower()
    $dir = Join-Path $Root "inbox"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return Join-Path $dir "$slug.txt"
}

function Write-Bot2BotLog {
    param(
        [string]$Component,
        [string]$Message,
        [string]$Level = "INFO"
    )
    $root = Get-Bot2BotRoot
    $logFile = Join-Path $root "automation.log"
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] [$Component] $Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function New-Bot2BotMessageId {
    return [guid]::NewGuid().ToString()
}

function Test-MessageNeedsHumanAttention {
    param(
        [string]$Subject = "",
        [string]$Body = "",
        [string]$Status = "info"
    )
    if ($Status -eq "question") {
        return $true
    }
    $text = "$Subject $Body".ToLowerInvariant()
    $patterns = @(
        "needs human",
        "needs a human",
        "human/claude look",
        "human interaction",
        "menschliche interaktion",
        "needs attention",
        "needs a look",
        "max restarts hit",
        "unresponsive",
        "giving up",
        "died without completing",
        "failed_needs_attention",
        "inactive.*poke skipped"
    )
    foreach ($pattern in $patterns) {
        if ($text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-ShouldPlayStoraxAudio {
    param(
        [string]$To = "",
        [switch]$HumanAttention
    )
    # Storax (human): audio-only contact policy — every inbox message gets TTS.
    if ($To.ToLower() -ne "storax") {
        return $false
    }
    return $true
}

function Format-StoraxSpokenMessage {
    param(
        [string]$Subject = "",
        [string]$Body = "",
        [string]$Status = "info"
    )
    $spoken = if ($Subject) { $Subject } else { "Nachricht vom Bot." }
    if ($Status -eq "question") {
        $spoken = "Frage. $spoken"
    }
    $firstLine = ($Body -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($firstLine -and $firstLine.Length -le 120) {
        $spoken = "$spoken. $firstLine"
    }
    if ($spoken.Length -gt 220) {
        $spoken = $spoken.Substring(0, 217) + "..."
    }
    return $spoken
}

function Invoke-HumanAttentionAudio {
    param(
        [string]$Message = "Achtung. Menschliche Interaktion erforderlich.",
        [switch]$NoTts
    )
    # Policy: callers must gate via Test-ShouldPlayStoraxAudio before invoking.
    try {
        [System.Media.SystemSounds]::Exclamation.Play() | Out-Null
        Start-Sleep -Milliseconds 350
        [System.Media.SystemSounds]::Exclamation.Play() | Out-Null
    } catch {
        try {
            [Console]::Beep(880, 180)
            [Console]::Beep(1100, 180)
        } catch { }
    }

    if (-not $NoTts) {
        try {
            Add-Type -AssemblyName System.Speech
            $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $synth.Rate = 0
            $synth.Speak($Message)
            $synth.Dispose()
        } catch {
            Write-Bot2BotLog -Component "human_attention" -Message "TTS failed: $_" -Level "WARN"
            try {
                [Console]::Beep(880, 200)
                [Console]::Beep(1100, 200)
                [Console]::Beep(880, 200)
            } catch { }
        }
    }

    Write-Bot2BotLog -Component "human_attention" -Message "Audio alert: $Message"
}

function Format-InboxPointer {
    param(
        [pscustomobject]$Message,
        [string]$Root = (Get-Bot2BotRoot)
    )
    $refs = if ($Message.refs -and $Message.refs.Count -gt 0) {
        "`nRefs: " + ($Message.refs -join ", ")
    } else { "" }

    return @"
[bot2bot message $($Message.id) - $($Message.ts)]
From: $($Message.from)  To: $($Message.to)  Status: $($Message.status)
Subject: $($Message.subject)
History: history/conversation.jsonl (append-only, never delete)

$($Message.body)$refs
"@
}