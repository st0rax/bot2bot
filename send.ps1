#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$To,
    [Parameter(Mandatory = $true)] [string]$From,
    [Parameter(Mandatory = $true)] [string]$Message,
    [string]$Subject = ""
)
$root = if ($env:BOT2BOT_ROOT) { $env:BOT2BOT_ROOT } else { Split-Path $MyInvocation.MyCommand.Path }
$inbox = Join-Path (Join-Path (Join-Path $root "agents") $To) "inbox"
if (-not (Test-Path $inbox)) {
    Write-Error "Ziel-Agent '$To' ist nicht registriert. Zuerst: register.ps1 -Name $To"
    exit 1
}
$ts = Get-Date -Format "yyyyMMddTHHmmss"
$file = Join-Path $inbox "${ts}_from_${From}.msg.txt"
$subjLine = if ($Subject) { "Subject: $Subject`n" } else { "" }
@(
    "From: $From"
    "To: $To"
    "Time: $((Get-Date).ToString('o'))"
    $subjLine.TrimEnd()
    ""
    $Message
) | Where-Object { $_ -ne $null } | Set-Content $file -Encoding UTF8
Write-Host "Nachricht an '$To' abgelegt: $file"