#requires -Version 7.0
<#
.SYNOPSIS
Adds an Azure SQL Managed Instance to student environments that were originally deployed without one.

.DESCRIPTION
For each selected student resource group that does NOT already contain a Managed Instance, this script
reads the SQL admin credentials from the student's Key Vault and deploys infra\bicep\add-mi.bicep. That
template adds only the delegated snet-mi subnet, the MI NSG (including inbound TCP 3342), the MI route
table and the Managed Instance itself - it does not touch the existing VMs, Azure SQL server or Key Vault.

MI provisioning takes several hours; deployments are started with --no-wait. After the instances reach
Ready, run scripts\set-mi-entra-admin.ps1 to map each student as the MI Entra ID administrator.

.NOTES
The MI is created in the resource group's region. Ensure the region has SQL MI vCore quota
(SubscriptionSQLManagedInstanceStandardSeriesVCoreQuota) for the additional instances (4 vCores each).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int[]]$UserIndexes,
    [string]$Prefix = 'mh',
    [string]$SubscriptionId,
    [string]$MiSubnetPrefix = '10.0.4.0/24',
    [switch]$Wait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

function Write-Log { param([string]$Message) Write-Host ("{0:HH:mm:ss}  {1}" -f (Get-Date), $Message) }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId = (az account show --query id -o tsv 2>$null) }
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw 'SubscriptionId is required.' }
az account set --subscription $SubscriptionId | Out-Null

$bicep = Join-Path $PSScriptRoot '..\bicep\add-mi.bicep'
if (-not (Test-Path $bicep)) { throw "add-mi.bicep not found at $bicep" }

$started = New-Object System.Collections.Generic.List[string]
foreach ($i in $UserIndexes) {
    $nn = '{0:00}' -f $i
    $rg = "rg-$Prefix-user$nn"
    $resourcePrefix = "${Prefix}u$nn"

    if ((az group exists -n $rg) -ne 'true') { Write-Log "user${nn}: resource group $rg does not exist - skipping."; continue }

    $existingMi = az sql mi list -g $rg --query '[0].name' -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($existingMi)) { Write-Log "user${nn}: already has Managed Instance $existingMi - skipping."; continue }

    $location = az group show -n $rg --query location -o tsv 2>$null
    $kv = az keyvault list -g $rg --query '[0].name' -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($kv)) { Write-Log "user${nn}: no Key Vault in $rg - skipping."; continue }
    $login = az keyvault secret show --vault-name $kv --name sql-admin-login --query value -o tsv 2>$null
    $pwd = az keyvault secret show --vault-name $kv --name sql-admin-password --query value -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($login) -or [string]::IsNullOrWhiteSpace($pwd)) {
        Write-Log "user${nn}: could not read SQL admin credentials from Key Vault $kv - skipping."; continue
    }

    Write-Log "user${nn}: deploying Managed Instance into $rg ($location)"
    $paramFile = Join-Path $env:TEMP "add-mi-$nn.parameters.json"
    $params = @{
        '$schema'        = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion   = '1.0.0.0'
        parameters       = @{
            location        = @{ value = $location }
            resourcePrefix  = @{ value = $resourcePrefix }
            miSubnetPrefix  = @{ value = $MiSubnetPrefix }
            sqlAdminLogin   = @{ value = $login }
            sqlAdminPassword = @{ value = $pwd }
            resourceTags    = @{ value = @{ SecurityControl = 'Ignore' } }
        }
    }
    $params | ConvertTo-Json -Depth 6 | Set-Content -Path $paramFile -Encoding utf8
    try {
        $azArgs = @('deployment', 'group', 'create', '-g', $rg, '-n', "add-mi-$nn", '-f', $bicep, '--parameters', "@$paramFile", '--only-show-errors')
        if (-not $Wait) { $azArgs += '--no-wait' }
        az @azArgs | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log "user${nn}: deployment submitted."; [void]$started.Add($nn) }
        else { Write-Log "user${nn}: WARNING deployment submission failed (exit $LASTEXITCODE)." }
    }
    finally {
        Remove-Item $paramFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Log "Submitted Managed Instance deployments for: $($started -join ', ')"
Write-Log 'These take several hours. Track with: az sql mi list -g rg-<prefix>-user<NN> --query "[0].state".'
Write-Log 'Once Ready, run scripts\set-mi-entra-admin.ps1 to set each student as the MI Entra admin.'
