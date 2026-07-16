# vote_fault.ps1
# Unanimous fault vote for an open intervention case.
#
# Usage:
#   .\vote_fault.ps1 -CaseId INT-001 -Voter grok -Fault grok -Reason "E in inbox nicht geprueft"
#   .\vote_fault.ps1 -CaseId INT-001 -Voter vibe -Fault grok -Reason "stimme zu"

param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [ValidateSet("grok", "vibe")]
    [string]$Voter,

    [Parameter(Mandatory)]
    [ValidateSet("grok", "vibe", "shared", "none")]
    [string]$Fault,

    [string]$Reason = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bot2bot_common.ps1")

$root = Get-Bot2BotRoot
$indexPath = Join-Path $root "data\leistungsindex.json"
$idx = Get-Content $indexPath -Raw | ConvertFrom-Json

$case = $idx.open_cases | Where-Object { $_.case_id -eq $CaseId } | Select-Object -First 1
if (-not $case) { throw "Open case not found: $CaseId" }
if ($case.status -ne "pending_unanimous") { throw "Case $CaseId status=$($case.status), not open for votes" }

if ($Voter -notin @($case.voters)) { throw "Voter $Voter not in voters list" }

$case.votes | Add-Member -NotePropertyName $Voter -NotePropertyValue ([ordered]@{
    fault  = $Fault
    reason = $Reason
    ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}) -Force

$voterList = @($case.voters)
$allVoted = ($voterList | ForEach-Object { $case.votes.PSObject.Properties.Name -contains $_ }) -notcontains $false

if ($allVoted) {
    $faults = $voterList | ForEach-Object { $case.votes.$_.fault }
    $unanimous = ($faults | Select-Object -Unique).Count -eq 1
    if ($unanimous) {
        $faultAgent = $faults[0]
        $case.verdict = "unanimous"
        $case.fault_agent = $faultAgent
        $case.status = "closed"

        $delta = 0
        if ($faultAgent -eq "grok") {
            $delta = [int]$idx.policy.penalties.fault_grok
            $idx.participants.grok.score += $delta
            $idx.participants.grok.fault_count += 1
        } elseif ($faultAgent -eq "vibe") {
            $delta = [int]$idx.policy.penalties.fault_vibe
            $idx.participants.vibe.score += $delta
            $idx.participants.vibe.fault_count += 1
        } elseif ($faultAgent -eq "shared") {
            $delta = [int]$idx.policy.penalties.fault_shared
            $idx.participants.grok.score += $delta
            $idx.participants.vibe.score += $delta
            $idx.participants.grok.fault_count += 1
            $idx.participants.vibe.fault_count += 1
        }
        $case.fault_delta = $delta

        $idx.events += [pscustomobject][ordered]@{
            id     = "$CaseId-fault"
            ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            kind   = "fault_verdict"
            agent  = $faultAgent
            delta  = $delta
            reason = "Einstimmig: $faultAgent ($Reason)"
            context = $CaseId
        }

        $idx.open_cases = @($idx.open_cases | Where-Object { $_.case_id -ne $CaseId })
        Write-Host "[leistungsindex] $CaseId CLOSED  fault=$faultAgent delta=$delta" -ForegroundColor Green
    } else {
        $case.status = "disputed"
        Write-Host "[leistungsindex] $CaseId DISPUTED  votes: $($faults -join ', '). Kein Malus bis Einstimmigkeit." -ForegroundColor Red
    }
} else {
    $missing = $voterList | Where-Object { $case.votes.PSObject.Properties.Name -notcontains $_ }
    Write-Host "[leistungsindex] Vote recorded ($Voter -> $Fault). Warte auf: $($missing -join ', ')" -ForegroundColor Cyan
}

$idx | ConvertTo-Json -Depth 10 | Set-Content -Path $indexPath -Encoding UTF8
Write-Bot2BotLog -Component "leistungsindex" -Message "Vote $Voter on $CaseId fault=$Fault status=$($case.status)"
