#requires -Version 7.0
<#
.SYNOPSIS
Maps each student as the Microsoft Entra ID administrator of their own Azure SQL Managed Instance.

.DESCRIPTION
For every student resource group that contains a SQL Managed Instance, this script:
  1. Grants the MI's system-assigned managed identity the Entra "Directory Readers" role. This is
     REQUIRED: without it, setting an Entra admin fails with
     "ServicePrincipalLookupInAadFailedIdentityForbidden". Granting it is front-loaded so the role
     can propagate while still-provisioning instances finish.
  2. Once the MI is Ready, sets the matching student (mhuser<NN>@<tenant>) as the MI's Entra admin,
     giving them admin over every database on their Managed Instance.

PREREQUISITE: The caller must be able to manage the Directory Readers role membership in Entra ID
(Global Administrator or Privileged Role Administrator). Creating Entra users already requires
elevated directory privileges, so the lab facilitator who runs deploy.ps1 -CreateUsers typically
has what is needed.

.NOTES
Idempotent: re-running re-applies the same membership/admin (Graph reports "already exist", which is
treated as success). `deploy.ps1` invokes this automatically after create-users when an MI is deployed.
#>
[CmdletBinding()]
param(
    [int]$UserCount = 30,
    [int]$StartIndex = 1,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$TenantDomain,
    [string]$Prefix = 'mh',
    [string]$SubscriptionId,
    # Poll each MI until it reaches the Ready state before setting the admin (MI provisioning is slow).
    [switch]$WaitForReady,
    [int]$TimeoutHours = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

function Write-Log { param([string]$Message) Write-Host ("{0:HH:mm:ss}  {1}" -f (Get-Date), $Message) }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId = (az account show --query id -o tsv 2>$null)
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw 'SubscriptionId is required.' }
az account set --subscription $SubscriptionId | Out-Null

# Resolve / activate the Directory Readers directory role and capture its (tenant-specific) id.
$directoryReadersTemplateId = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'
$roles = az rest --method get --url 'https://graph.microsoft.com/v1.0/directoryRoles' -o json 2>$null | ConvertFrom-Json
$directoryReaders = $roles.value | Where-Object { $_.roleTemplateId -eq $directoryReadersTemplateId }
if (-not $directoryReaders) {
    Write-Log 'Activating the Directory Readers directory role.'
    $activateFile = Join-Path $env:TEMP 'mh-dr-activate.json'
    ('{"roleTemplateId":"' + $directoryReadersTemplateId + '"}') | Set-Content -Path $activateFile -Encoding ascii -NoNewline
    $directoryReaders = az rest --method post --url 'https://graph.microsoft.com/v1.0/directoryRoles' --headers 'Content-Type=application/json' --body "@$activateFile" -o json 2>$null | ConvertFrom-Json
    Remove-Item $activateFile -Force -ErrorAction SilentlyContinue
}
if (-not $directoryReaders -or [string]::IsNullOrWhiteSpace($directoryReaders.id)) {
    throw 'Could not resolve the Directory Readers role. The caller likely lacks directory-role privileges (need Global Administrator or Privileged Role Administrator).'
}
$roleId = $directoryReaders.id

function Grant-DirectoryReaders {
    param([Parameter(Mandatory = $true)][string]$PrincipalId, [Parameter(Mandatory = $true)][string]$Tag)
    $bodyFile = Join-Path $env:TEMP "mh-dr-$Tag.json"
    ('{"@odata.id":"https://graph.microsoft.com/v1.0/directoryObjects/' + $PrincipalId + '"}') | Set-Content -Path $bodyFile -Encoding ascii -NoNewline
    $url = "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/`$ref"
    $out = az rest --method post --url $url --headers 'Content-Type=application/json' --body "@$bodyFile" 2>&1
    Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -eq 0) { Write-Log "  Directory Readers granted to MI identity ($Tag)."; return $true }
    if ($out -match 'already exist') { Write-Log "  Directory Readers already granted ($Tag)."; return $true }
    Write-Log "  WARNING: failed to grant Directory Readers ($Tag): $out"
    return $false
}

# Build the work list (resource groups that actually contain a Managed Instance).
$endIndex = $StartIndex + $UserCount - 1
$work = New-Object System.Collections.Generic.List[object]
for ($i = $StartIndex; $i -le $endIndex; $i++) {
    $nn = '{0:00}' -f $i
    $rg = "rg-$Prefix-user$nn"
    $mi = az sql mi list -g $rg --query '[0].name' -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($mi)) { Write-Log "user${nn}: no Managed Instance in $rg - skipping."; continue }
    $upn = "${Prefix}user$nn@$TenantDomain"
    $oid = az ad user show --id $upn --query id -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($oid)) { Write-Log "user${nn}: student $upn not found in Entra - skipping."; continue }
    $miPrincipalId = az sql mi show -g $rg -n $mi --query 'identity.principalId' -o tsv 2>$null
    $work.Add([pscustomobject]@{ nn = $nn; rg = $rg; mi = $mi; upn = $upn; oid = $oid; miPid = $miPrincipalId; done = $false }) | Out-Null
}
Write-Log "Managed Instances to process: $($work.Count)"

# Phase 1: grant Directory Readers to each MI identity (front-loaded, idempotent).
foreach ($w in $work) {
    if ([string]::IsNullOrWhiteSpace($w.miPid)) { Write-Log "user$($w.nn): MI identity not available yet - will rely on retry."; continue }
    Write-Log "user$($w.nn): ensuring Directory Readers for MI $($w.mi)"
    [void](Grant-DirectoryReaders -PrincipalId $w.miPid -Tag $w.nn)
}

# Phase 2: set the student as Entra admin, once the MI is Ready.
$deadline = (Get-Date).AddHours($TimeoutHours)
do {
    foreach ($w in ($work | Where-Object { -not $_.done })) {
        # Self-correct: if the admin is already set (e.g. a prior pass or run), mark done.
        $current = az sql mi ad-admin list -g $w.rg --mi $w.mi --query '[0].login' -o tsv 2>$null
        if ($current -eq $w.upn) { $w.done = $true; continue }
        $state = az sql mi show -g $w.rg -n $w.mi --query 'state' -o tsv 2>$null
        if ($state -ne 'Ready') {
            if (-not $WaitForReady) { Write-Log "user$($w.nn): MI state '$state' (not Ready); skipping (no -WaitForReady)." }
            continue
        }
        $result = az sql mi ad-admin create -g $w.rg --mi $w.mi -u $w.upn -i $w.oid --only-show-errors 2>&1
        if ($LASTEXITCODE -eq 0) { $w.done = $true; Write-Log "user$($w.nn): Entra admin set -> $($w.upn)" }
        elseif ($result -match 'IdentityForbidden|Directory Readers') { Write-Log "user$($w.nn): waiting on Directory Readers propagation." }
        else { Write-Log "user$($w.nn): WARNING ad-admin set failed: $result" }
    }
    $pending = ($work | Where-Object { -not $_.done }).Count
    if ($pending -eq 0) { break }
    if (-not $WaitForReady) { break }
    Write-Log "Pending Managed Instances (not Ready / not set): $pending"
    Start-Sleep -Seconds 180
} while ((Get-Date) -lt $deadline)

$set = ($work | Where-Object { $_.done }).Count
Write-Log "Completed. Entra admin set on $set/$($work.Count) Managed Instances."
$work | Where-Object { -not $_.done } | ForEach-Object { Write-Log "STILL PENDING: user$($_.nn) ($($_.mi))" }
if ($set -lt $work.Count -and $WaitForReady) { exit 1 }
