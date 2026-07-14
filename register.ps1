#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)
$root = if ($env:BOT2BOT_ROOT) { $env:BOT2BOT_ROOT } else { Split-Path $MyInvocation.MyCommand.Path }
$agentsRoot = Join-Path $root "agents"
$agentDir = Join-Path $agentsRoot $Name
$inbox    = Join-Path $agentDir "inbox"
$outbox   = Join-Path $agentDir "outbox"
$state    = Join-Path $agentDir "state.json"

if ($Name -notmatch '^[a-z][a-z0-9_-]{0,31}$') {
    Write-Error "Ungueltiger Agent-Slug: $Name"
    exit 1
}

if (Test-Path $agentDir) {
    Write-Host "Agent '$Name' ist bereits registriert ($agentDir)."
    exit 0
}
New-Item -ItemType Directory -Force -Path $inbox  | Out-Null
New-Item -ItemType Directory -Force -Path $outbox | Out-Null
[pscustomobject]@{
    name       = $Name
    registered = (Get-Date).ToString("o")
    lastSeen   = $null
    processed  = @()
} | ConvertTo-Json | Set-Content $state -Encoding UTF8
Write-Host "Agent '$Name' registriert: $agentDir"