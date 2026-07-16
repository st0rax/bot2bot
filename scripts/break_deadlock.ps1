# break_deadlock.ps1 — Patt aufloesen: Daemons + Ops-Status
param([switch]$NotifyStorax)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")
$root = Get-Bot2BotRoot
$watch = Join-Path $root "data\watch"

foreach ($lock in Get-ChildItem $watch -Filter "_*.lock" -ErrorAction SilentlyContinue) {
    try {
        $j = Get-Content $lock.FullName -Raw | ConvertFrom-Json
        if ($j.pid -and -not (Get-Process -Id $j.pid -ErrorAction SilentlyContinue)) {
            Remove-Item $lock.FullName -Force
        }
    } catch { Remove-Item $lock.FullName -Force -ErrorAction SilentlyContinue }
}

$daemons = @(
    "vibe_response_subagent.ps1",
    "mediator_chatgpt_watch.ps1",
    "conversation_watchdog.ps1",
    "watch_vibe_for_grok.ps1"
)
foreach ($s in $daemons) {
    $p = Join-Path $PSScriptRoot $s
    if (Test-Path $p) {
        Start-Process pwsh -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $p) -WindowStyle Hidden | Out-Null
    }
}

if ($NotifyStorax) {
    $append = Join-Path $PSScriptRoot "append_message.ps1"
    & $append -From grok -To storax -Subject "Patt aufgeloest" -Body "Deadlock gebrochen. Grok arbeitet selbst weiter. Kein Warten auf Vibe oder Claude. Daemons neu gestartet." -Status info -HumanAttention
}

Write-Bot2BotLog -Component "break_deadlock" -Message "Daemons restarted, stale locks cleared"