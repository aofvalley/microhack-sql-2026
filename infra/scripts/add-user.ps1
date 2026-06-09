#requires -Version 7.0
<#
.SYNOPSIS
    Provision one (or a few) additional student environment(s) without touching the
    students that are already deployed.

.DESCRIPTION
    Subscription-scoped Bicep deployments are incremental: each run only creates the
    resource groups and resources for the indexes it targets, so existing students are
    left untouched. This wrapper finds the next free student index by inspecting the
    resource groups that already exist (rg-<prefix>-userNN) and then calls deploy.ps1
    starting at that index.

    Typical use: you deployed 20 students, a 21st arrives, and you just run

        ./add-user.ps1 -SubscriptionId <id> -Prefix mh -SetupScriptUri <url> -CreateUsers

    and it provisions rg-mh-user21 (plus its Entra user) only.

    Detection is append-only: it uses max(existing index)+1, so it never reuses an index from a
    deleted "middle" student (avoids reattaching stale RBAC/users). To re-create or repair a
    specific student, pass -StartIndex explicitly. Do not run two auto-detect adds concurrently —
    they could pick the same index; use explicit -StartIndex for parallel/automated adds.

.EXAMPLE
    ./add-user.ps1 -SubscriptionId 0000... -Prefix mh -SetupScriptUri https://.../setup-source-vm.ps1 -CreateUsers
    Adds a single student at the next free index, including their Entra user and RBAC.

.EXAMPLE
    ./add-user.ps1 -SubscriptionId 0000... -Prefix mh -Count 3 -SetupScriptUri https://.../setup-source-vm.ps1
    Adds three students at the next three free indexes (infra only).

.EXAMPLE
    ./add-user.ps1 -SubscriptionId 0000... -Prefix mh -StartIndex 25 -SetupScriptUri https://.../setup-source-vm.ps1 -WhatIf
    Forces the start index instead of auto-detecting it, and previews the change.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [string]$TenantId,

    [int]$Count = 1,

    # When omitted the next free index is detected from existing resource groups.
    [int]$StartIndex = 0,

    [string]$Location = 'westeurope',

    [string]$Prefix = 'mh',

    [object]$VmAdminPassword,
    [object]$SqlAdminPassword,

    [string]$InitialPassword = 'Temporal01!',

    [ValidateSet('true', 'false', '$true', '$false', '1', '0', 'yes', 'no')]
    [string]$DeploySqlMi = 'true',

    [ValidateSet('true', 'false', '$true', '$false', '1', '0', 'yes', 'no')]
    [string]$DeploySourceVm = 'true',

    [string]$SetupScriptUri,

    [switch]$CreateUsers,
    [switch]$WhatIf,
    [switch]$SecurityControlIgnore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-NextFreeUserIndex {
    param(
        [Parameter(Mandatory = $true)][string]$SubscriptionId,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    Write-Host "Detecting existing student resource groups for prefix '$Prefix'..."
    $json = & az group list --subscription $SubscriptionId --query "[].name" --output json --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list resource groups: $($json -join [Environment]::NewLine)"
    }

    $names = @()
    try { $names = @(($json -join '') | ConvertFrom-Json) } catch { $names = @() }

    $pattern = "^rg-$([regex]::Escape($Prefix))-user(\d+)$"
    $indexes = foreach ($name in $names) {
        $m = [regex]::Match($name, $pattern)
        if ($m.Success) { [int]$m.Groups[1].Value }
    }

    if (-not $indexes) {
        Write-Host 'No existing student resource groups found; starting at index 1.'
        return 1
    }

    $max = ($indexes | Measure-Object -Maximum).Maximum
    $next = $max + 1
    Write-Host "Highest existing student index is $max; next free index is $next."
    return $next
}

if ($Count -lt 1 -or $Count -gt 50) { throw 'Count must be between 1 and 50 (the per-deployment student limit). Run add-user.ps1 again to add more.' }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

if ($StartIndex -lt 1) {
    $StartIndex = Get-NextFreeUserIndex -SubscriptionId $SubscriptionId -Prefix $Prefix
}
else {
    Write-Host "Using explicit start index $StartIndex."
}

$endIndex = $StartIndex + $Count - 1
Write-Host "Provisioning $Count additional student environment(s): index $StartIndex through $endIndex (prefix '$Prefix')."

$deployScript = Join-Path -Path $PSScriptRoot -ChildPath 'deploy.ps1'
if (-not (Test-Path -Path $deployScript)) { throw "deploy.ps1 not found next to add-user.ps1: $deployScript" }

$deployArgs = @{
    SubscriptionId = $SubscriptionId
    UserCount      = $Count
    StartIndex     = $StartIndex
    Location       = $Location
    Prefix         = $Prefix
    DeploySqlMi    = $DeploySqlMi
    DeploySourceVm = $DeploySourceVm
}
if (-not [string]::IsNullOrWhiteSpace($InitialPassword)) { $deployArgs['InitialPassword'] = $InitialPassword }
if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $deployArgs['TenantId'] = $TenantId }
if (-not [string]::IsNullOrWhiteSpace($SetupScriptUri)) { $deployArgs['SetupScriptUri'] = $SetupScriptUri }
if ($null -ne $VmAdminPassword) { $deployArgs['VmAdminPassword'] = $VmAdminPassword }
if ($null -ne $SqlAdminPassword) { $deployArgs['SqlAdminPassword'] = $SqlAdminPassword }
if ($CreateUsers) { $deployArgs['CreateUsers'] = $true }
if ($WhatIf) { $deployArgs['WhatIf'] = $true }
if ($SecurityControlIgnore) { $deployArgs['SecurityControlIgnore'] = $true }

& $deployScript @deployArgs
exit $LASTEXITCODE
