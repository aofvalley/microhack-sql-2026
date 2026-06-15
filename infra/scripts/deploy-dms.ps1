#requires -Version 7.0
<#
.SYNOPSIS
    Provisions one Azure Database Migration Service (SQL Migration Service) per student
    resource group and grants each student Contributor on their own DMS.

.DESCRIPTION
    For each user index NN (zero-padded) the script:
      1. Creates DMS  <prefix>u<NN>-dms  in  rg-<prefix>-user<NN>  (idempotent: skips if it exists).
      2. Resolves the student UPN  <prefix>user<NN>@<TenantDomain>  to an object id.
      3. Assigns the built-in Contributor role to that user, scoped to the DMS resource.

    The DMS location defaults to the resource group's location, so labs spread across
    multiple regions are handled automatically. Override with -Location to force one region.

    Required tooling: Azure CLI signed in (az login) and the 'datamigration' extension
    (installed automatically if missing). The Microsoft.DataMigration provider is registered.

.EXAMPLE
    pwsh .\scripts\deploy-dms.ps1 `
      -TenantDomain 'MngEnvMCAP400602.onmicrosoft.com' `
      -UserCount 30 -StartIndex 1 -Prefix 'mh'

.EXAMPLE
    pwsh .\scripts\deploy-dms.ps1 -TenantDomain 'contoso.onmicrosoft.com' -UserCount 5 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantDomain,
    [int]$UserCount = 30,
    [int]$StartIndex = 1,
    [string]$Prefix = 'mh',
    [string]$SubscriptionId,
    [string]$Location,
    [string]$Role = 'Contributor',
    [int]$ThrottleLimit = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ($SubscriptionId) {
    Write-Host "Setting subscription context to $SubscriptionId"
    az account set --subscription $SubscriptionId --only-show-errors | Out-Null
}

# Ensure the datamigration extension and resource provider are ready.
if (-not (az extension show --name datamigration --query name -o tsv 2>$null)) {
    Write-Host 'Installing Azure CLI extension: datamigration'
    az extension add --name datamigration --only-show-errors | Out-Null
}
Write-Host 'Ensuring Microsoft.DataMigration provider is registered'
az provider register --namespace Microsoft.DataMigration --only-show-errors | Out-Null

# Build the work list.
$items = $StartIndex..($StartIndex + $UserCount - 1) | ForEach-Object {
    $nn = '{0:D2}' -f $_
    [pscustomobject]@{
        NN  = $nn
        RG  = "rg-$Prefix-user$nn"
        DMS = "${Prefix}u$nn-dms"
        UPN = "${Prefix}user$nn@$TenantDomain"
        Loc = $Location   # may be empty -> resolved from the RG below
    }
}

if ($PSCmdlet.ShouldProcess("$UserCount student environments", "Create DMS + assign $Role")) {

    $results = $items | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $i = $_
        $role = $using:Role

        # Resolve the DMS location from the resource group when not forced.
        $loc = $i.Loc
        if (-not $loc) {
            $loc = az group show -n $i.RG --query location -o tsv 2>$null
            if (-not $loc) { return [pscustomobject]@{ NN = $i.NN; DMS = $i.DMS; Status = 'RG_NOT_FOUND' } }
        }

        # 1. Create DMS (idempotent).
        $dmsId = az datamigration sql-service show -g $i.RG -n $i.DMS --query id -o tsv 2>$null
        $dmsState = 'DMS_EXISTS'
        if (-not $dmsId) {
            $dmsId = az datamigration sql-service create -g $i.RG -n $i.DMS -l $loc --query id -o tsv 2>&1
            if ($LASTEXITCODE -ne 0) {
                return [pscustomobject]@{ NN = $i.NN; DMS = $i.DMS; Status = "DMS_FAIL: $dmsId" }
            }
            $dmsState = 'DMS_CREATED'
        }

        # 2. Resolve the student object id.
        $oid = az ad user show --id $i.UPN --query id -o tsv 2>$null
        if (-not $oid) {
            return [pscustomobject]@{ NN = $i.NN; DMS = $i.DMS; Status = "$dmsState | USER_NOT_FOUND" }
        }

        # 3. Assign the role scoped to the DMS (idempotent at the platform level).
        $null = az role assignment create `
            --assignee-object-id $oid `
            --assignee-principal-type User `
            --role $role `
            --scope $dmsId `
            --only-show-errors 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ NN = $i.NN; DMS = $i.DMS; Status = "$dmsState | ROLE_FAIL" }
        }

        return [pscustomobject]@{ NN = $i.NN; DMS = $i.DMS; Status = "$dmsState | ROLE_OK" }
    }

    $results | Sort-Object NN | Format-Table -AutoSize
    $failures = $results | Where-Object { $_.Status -notlike '*ROLE_OK*' }
    if ($failures) {
        Write-Warning "$($failures.Count) item(s) need attention."
        exit 1
    }
    Write-Host "All $UserCount DMS instances created and $Role assigned."
}
