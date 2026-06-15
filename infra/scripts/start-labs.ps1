#requires -Version 7.0
<#
.SYNOPSIS
    Start (power on) every student lab VM across the cohort without changing or
    deleting any resource.

.DESCRIPTION
    Each student environment has two source SQL Server VMs (rg-<prefix>-userNN:
    <prefix>uNN-srcvm19 and <prefix>uNN-srcvm25). The VMs auto-shut-down every
    evening (DevTestLab schedule) to control cost, so before a lab day you start
    them all back up with this script.

    By default it DISCOVERS every rg-<prefix>-user* resource group and starts all
    VMs it finds, so it scales to any cohort size. Use -StartIndex/-UserCount to
    target a fixed range instead. Nothing is created, modified or deleted: this
    only issues `az vm start` on existing, deallocated VMs.

    Pair it with stop-labs.ps1, which deallocates the same VMs at the end of the day.

.EXAMPLE
    ./start-labs.ps1 -SubscriptionId 0000... -Prefix mhlab
    Start every VM in every rg-mhlab-user* resource group.

.EXAMPLE
    ./start-labs.ps1 -SubscriptionId 0000... -Prefix mhlab -StartIndex 1 -UserCount 30
    Start the VMs for students 1..30 only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
    [string]$Prefix = 'mh',
    [int]$UserCount = 0,
    [int]$StartIndex = 1,
    [switch]$Wait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Az {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $azArguments = @($Arguments) + @('--only-show-errors')
    $output = & az @azArguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "az $($Arguments -join ' ') failed with exit code $exitCode. $($output -join [Environment]::NewLine)"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

try {
    if ($Prefix -notmatch '^[a-z0-9]+$') { throw 'Prefix must contain only lowercase letters and numbers.' }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

    Write-Host "Setting Azure subscription to $SubscriptionId"
    Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

    # Build the list of target resource groups.
    $resourceGroups = New-Object System.Collections.Generic.List[string]
    if ($UserCount -gt 0) {
        for ($index = $StartIndex; $index -le ($StartIndex + $UserCount - 1); $index++) {
            $resourceGroups.Add("rg-$Prefix-user$($index.ToString('00'))") | Out-Null
        }
    }
    else {
        Write-Host "Discovering resource groups matching rg-$Prefix-user*"
        $found = Invoke-Az -Arguments @(
            'group', 'list',
            '--query', "[?starts_with(name, 'rg-$Prefix-user')].name",
            '--output', 'tsv'
        )
        @($found.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object) |
            ForEach-Object { $resourceGroups.Add($_) | Out-Null }
    }

    if ($resourceGroups.Count -eq 0) {
        Write-Host 'No matching lab resource groups found. Nothing to start.'
        return
    }

    Write-Host "Starting VMs in $($resourceGroups.Count) resource group(s)..."
    $started = 0
    $missing = 0
    foreach ($rg in $resourceGroups) {
        $group = Invoke-Az -Arguments @('group', 'show', '--name', $rg, '--output', 'none') -AllowFailure
        if ($group.ExitCode -ne 0) {
            Write-Host "  $rg not found. Skipping."
            $missing++
            continue
        }

        $vms = Invoke-Az -Arguments @('vm', 'list', '--resource-group', $rg, '--query', '[].name', '--output', 'tsv')
        $vmNames = @($vms.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        if ($vmNames.Count -eq 0) {
            Write-Host "  $rg has no VMs. Skipping."
            continue
        }

        foreach ($vm in $vmNames) {
            Write-Host "  Starting $rg/$vm"
            # --no-wait by default so all VMs power on in parallel; -Wait blocks per VM.
            $startArgs = @('vm', 'start', '--resource-group', $rg, '--name', $vm, '--output', 'none')
            if (-not $Wait) { $startArgs += '--no-wait' }
            Invoke-Az -Arguments $startArgs | Out-Null
            $started++
        }
    }

    Write-Host 'Start summary:'
    Write-Host "  VM start requests issued: $started"
    Write-Host "  Resource groups missing/skipped: $missing"
    if (-not $Wait) {
        Write-Host 'VMs are starting in the background (--no-wait). Allow a few minutes before connecting.'
    }
}
catch {
    Write-Error $_
    exit 1
}
