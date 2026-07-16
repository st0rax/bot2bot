# pick_nagger_agent.ps1 - Waehlt besten WebBrain-Nagger aus History + Registry
param([string]$Root = "")

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")
if (-not $Root) { $Root = Get-Bot2BotRoot }

$hist = Get-HistoryPath -Root $Root
$msgs = if (Test-Path $hist) {
    @(Get-Content $hist | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ })
} else { @() }

$since = (Get-Date).ToUniversalTime().AddHours(-12)
$registry = Get-AgentRegistry -Root $Root
$scores = [System.Collections.Generic.List[object]]::new()

foreach ($prop in $registry.PSObject.Properties) {
    $b = $prop.Name
    $cfg = Get-AgentConfig -AgentName $b -Root $Root
    if (-not $cfg.Active -or $cfg.Kind -ne "webbrain") { continue }

    $recent = @($msgs | Where-Object { [datetime]::Parse($_.ts).ToUniversalTime() -ge $since })
    $out = @($recent | Where-Object { $_.from -eq $b }).Count
    $in = @($recent | Where-Object { $_.to -eq $b }).Count

    $replyMin = 9999.0
    $inLast = $msgs | Where-Object { $_.to -eq $b } | Select-Object -Last 1
    if ($inLast) {
        $inTs = [datetime]::Parse($inLast.ts).ToUniversalTime()
        $rep = $msgs | Where-Object {
            $_.from -eq $b -and [datetime]::Parse($_.ts).ToUniversalTime() -ge $inTs
        } | Select-Object -First 1
        if ($rep) {
            $replyMin = ([datetime]::Parse($rep.ts).ToUniversalTime() - $inTs).TotalMinutes
        }
    }

    $score = 0.0
    $score += $out * 4.0
    $score += $in * 1.0
    if ($replyMin -lt 9999) { $score += [math]::Max(0, 30 - $replyMin) }
    if ($b -eq "chatgpt") { $score += 20 }  # mediator/caretaker role
    if ($b -eq "kimi") { $score += 8 }       # reliable diagnose runs in project history
    if ($b -eq "gemini") { $score += 5 }

    [void]$scores.Add([pscustomobject]@{
        agent    = $b
        out_12h  = $out
        in_12h   = $in
        reply_min = if ($replyMin -lt 9999) { [math]::Round($replyMin, 1) } else { $null }
        score    = [math]::Round($score, 1)
        reason   = if ($b -eq "chatgpt") { "mediator+caretaker" } elseif ($b -eq "kimi") { "diagnose-reliable" } else { "active-webbrain" }
    })
}

$ranked = @($scores | Sort-Object score -Descending)
if (-not $ranked.Count) { throw "Kein aktiver WebBrain fuer Nagger" }

$result = [pscustomobject]@{
    primary   = $ranked[0].agent
    backups   = @($ranked | Select-Object -Skip 1 | ForEach-Object { $_.agent })
    ranked    = $ranked
    picked_at = (Get-Date).ToUniversalTime().ToString("o")
}
$result | ConvertTo-Json -Depth 4
exit 0