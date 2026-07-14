# notify_speak.ps1
# Audible notification via built-in Windows TTS (no third-party tools).
# Tries WinRT natural voices first (if installed), else SAPI Clear SSML.
# -Clear/-Best: agreed default until Natural Voice installed (medium/0/280ms).
#   -Best tries WinRT natural voice first, then falls back to this SAPI profile.
#
# Usage:
#   .\notify_speak.ps1 -Message "Kurze Info." -Best
#   .\notify_speak.ps1 -Message "Text" -Clear
#   .\notify_speak.ps1 -Message "Hello" -VoiceCulture en-US

param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [string]$VoiceCulture = "de-DE",

    [ValidateRange(-10, 10)]
    [int]$Rate = 0,

    [ValidateRange(0, 100)]
    [int]$Volume = 100,

    [ValidateRange(1, 5)]
    [int]$Repeat = 1,

    [switch]$Clear,
    [switch]$Best
)

$ErrorActionPreference = "Stop"

function Get-ProsodyProfile {
    param([bool]$NaturalVoice)
    $cfg = Get-TtsConfig
    if ($NaturalVoice -and $cfg -and $cfg.prosody_natural) {
        return @{
            rate      = if ($cfg.prosody_natural.rate) { $cfg.prosody_natural.rate } else { '92%' }
            pitch     = if ($cfg.prosody_natural.pitch) { $cfg.prosody_natural.pitch } else { '-1st' }
            volume    = if ($cfg.prosody_natural.volume) { $cfg.prosody_natural.volume } else { '95%' }
            break_ms  = if ($cfg.prosody_natural.break_ms) { [int]$cfg.prosody_natural.break_ms } else { 380 }
            sapi_rate = if ($null -ne $cfg.prosody_natural.sapi_rate) { [int]$cfg.prosody_natural.sapi_rate } else { -1 }
        }
    }
    return @{
        rate      = 'medium'
        pitch     = 'default'
        volume    = 'default'
        break_ms  = 280
        sapi_rate = 0
    }
}

function ConvertTo-ClearSsml {
    param([string]$Text, [string]$Culture, [hashtable]$Prosody)
    $parts = $Text -split '(?<=[.!?])\s+' | Where-Object { $_.Trim() }
    if ($parts.Count -le 1) {
        $escaped = [System.Security.SecurityElement]::Escape($Text)
        return @"
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$Culture">
<prosody rate="$($Prosody.rate)" pitch="$($Prosody.pitch)" volume="$($Prosody.volume)">$escaped</prosody>
</speak>
"@
    }
    $body = ($parts | ForEach-Object {
        $p = [System.Security.SecurityElement]::Escape($_.Trim())
        "<prosody rate=`"$($Prosody.rate)`" pitch=`"$($Prosody.pitch)`" volume=`"$($Prosody.volume)`">$p</prosody><break time=`"$($Prosody.break_ms)ms`"/>"
    }) -join "`n"
    return @"
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$Culture">
$body
</speak>
"@
}

function Invoke-WinRtSpeak {
    param([string]$Text, [string]$Culture)
    [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime] | Out-Null
    [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime] | Out-Null
    $synth = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::new()
    $voices = @($synth.AllVoices)
    if ($voices.Count -eq 0) { return $false }
    $pick = $voices | Where-Object { $_.Language -eq $Culture } | Select-Object -First 1
    if (-not $pick) {
        $pick = $voices | Where-Object { $_.Language -like ($Culture.Split('-')[0] + '*') } | Select-Object -First 1
    }
    if (-not $pick) { $pick = $voices | Select-Object -First 1 }
    $synth.Voice = $pick
    try { $synth.Options.SpeakingRate = 2.0 } catch { }
    $stream = $synth.SynthesizeTextToStreamAsync($Text).GetAwaiter().GetResult()
    $player = [Windows.Media.Playback.MediaPlayer]::new()
    $player.Volume = $Volume / 100.0
    $player.SetStreamSource($stream)
    $player.Play()
    $secs = [Math]::Min(120, [Math]::Max(4, [int]($Text.Length / 12)))
    Start-Sleep -Seconds $secs
    $player.Pause()
    Write-Host "[notify_speak] WinRT: $($pick.DisplayName) ($($pick.Language))" -ForegroundColor Cyan
    return $true
}

function Get-TtsConfig {
    $cfgPath = Join-Path $PSScriptRoot "logs\audio\tts_config.json"
    if (Test-Path $cfgPath) {
        try { return Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { }
    }
    return $null
}

function Resolve-SapiVoice {
    param([string]$Culture, [System.Speech.Synthesis.SpeechSynthesizer]$Synth, [bool]$PreferNatural)
    $cfg = Get-TtsConfig
    if ($cfg -and $cfg.approval_status -eq 'approved' -and $cfg.voice_natural) {
        try { $Synth.SelectVoice($cfg.voice_natural); return $cfg.voice_natural } catch { }
    }
    if (-not $PreferNatural) {
        $hedda = $Synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Name -match 'Hedda' } | Select-Object -First 1
        if ($hedda) { return $hedda.VoiceInfo.Name }
    }
    $all = $Synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq $Culture -and $_.Enabled }
    $natural = $all | Where-Object { $_.VoiceInfo.Name -match 'Katja' } | Select-Object -First 1
    if ($natural) { return $natural.VoiceInfo.Name }
    $desktop = $all | Where-Object { $_.VoiceInfo.Name -match 'Hedda' } | Select-Object -First 1
    if ($desktop) { return $desktop.VoiceInfo.Name }
    return ($all | Select-Object -First 1).VoiceInfo.Name
}

function Invoke-SapiSpeak {
    param([string]$Text, [string]$Culture, [bool]$UseClear, [int]$SpeechRate)
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $voiceName = Resolve-SapiVoice -Culture $Culture -Synth $synth -PreferNatural:$Best
    if ($voiceName) { $synth.SelectVoice($voiceName) }
    $isNatural = $voiceName -match 'Katja|Amala|Seraphina|Online'
    $prosody = Get-ProsodyProfile -NaturalVoice:$isNatural
    if ($UseClear) {
        $synth.Rate = if ($SpeechRate -eq 0) { $prosody.sapi_rate } else { $SpeechRate }
    } else {
        $synth.Rate = $SpeechRate
    }
    $synth.Volume = $Volume
    if ($UseClear) {
        $ssml = ConvertTo-ClearSsml -Text $Text -Culture $Culture -Prosody $prosody
        try { $synth.SpeakSsml($ssml) } catch { $synth.Speak($Text) }
    } else {
        $synth.Speak($Text)
    }
    Write-Host "[notify_speak] SAPI: $voiceName (Clear=$UseClear natural=$isNatural rate=$($prosody.rate))" -ForegroundColor Cyan
}

$useClear = $Clear -or $Best

try {
    for ($i = 0; $i -lt $Repeat; $i++) {
        $spoken = $false
        if ($Best) {
            try { $spoken = Invoke-WinRtSpeak -Text $Message -Culture $VoiceCulture } catch { $spoken = $false }
        }
        if (-not $spoken) {
            Invoke-SapiSpeak -Text $Message -Culture $VoiceCulture -UseClear $useClear -SpeechRate $Rate
        }
    }
    Write-Host "[notify_speak] OK" -ForegroundColor Green
    exit 0
}
catch {
    Write-Error $_
    exit 1
}