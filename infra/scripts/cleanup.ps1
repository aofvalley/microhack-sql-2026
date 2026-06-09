#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
    [string]$Prefix = 'mh',
    [int]$UserCount = 30,
    [int]$StartIndex = 1,
    [switch]$DeleteUsers,
    [string]$TenantDomain,
    [switch]$All,
    [switch]$IncludeStaging,
    [switch]$Force
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
    if ($UserCount -lt 1) { throw 'UserCount must be at least 1.' }
    if ($StartIndex -lt 1) { throw 'StartIndex must be at least 1.' }
    if ($Prefix -notmatch '^[a-z0-9]+$') { throw 'Prefix must contain only lowercase letters and numbers.' }
    if ($DeleteUsers -and [string]::IsNullOrWhiteSpace($TenantDomain)) { throw 'TenantDomain is required when -DeleteUsers is used.' }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

    Write-Host "Setting Azure subscription to $SubscriptionId"
    Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

    $targets = New-Object System.Collections.Generic.List[object]
    if ($All) {
        # Discover every lab resource group for this prefix, regardless of count.
        Write-Host "Discovering resource groups matching rg-$Prefix-user*"
        $found = Invoke-Az -Arguments @(
            'group', 'list',
            '--query', "[?starts_with(name, 'rg-$Prefix-user')].name",
            '--output', 'tsv'
        )
        $names = @($found.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object)
        foreach ($name in $names) {
            $nn = ($name -replace "^rg-$Prefix-user", '')
            $targets.Add([pscustomobject]@{
                Index         = $nn
                ResourceGroup = $name
                UserPrincipal = if ($DeleteUsers) { "${Prefix}user$nn@$TenantDomain" } else { $null }
            }) | Out-Null
        }
        if ($targets.Count -eq 0) {
            Write-Host 'No matching resource groups found.'
            if (-not ($All -or $IncludeStaging)) { return }
        }
    }
    else {
        for ($index = $StartIndex; $index -le ($StartIndex + $UserCount - 1); $index++) {
            $nn = $index.ToString('00')
            $targets.Add([pscustomobject]@{
                Index         = $index
                ResourceGroup = "rg-$Prefix-user$nn"
                UserPrincipal = if ($DeleteUsers) { "${Prefix}user$nn@$TenantDomain" } else { $null }
            }) | Out-Null
        }
    }

    Write-Host 'The following resource groups will be deleted with --no-wait:'
    $targets | ForEach-Object { Write-Host "  $($_.ResourceGroup)" }
    if ($DeleteUsers) {
        Write-Host 'The following Entra users will be deleted:'
        $targets | ForEach-Object { Write-Host "  $($_.UserPrincipal)" }
    }

    if (-not $Force) {
        $confirmation = Read-Host "Type YES to delete $($targets.Count) resource group(s)"
        if ($confirmation -ne 'YES') {
            Write-Host 'Cleanup cancelled.'
            return
        }
    }

    $rgDeleteStarted = 0
    $rgMissing = 0
    $vaultPurged = 0
    $userDeleted = 0
    $userMissing = 0

    foreach ($target in $targets) {
        Write-Host "Deleting resource group $($target.ResourceGroup)"
        $group = Invoke-Az -Arguments @('group', 'show', '--name', $target.ResourceGroup, '--output', 'none') -AllowFailure
        if ($group.ExitCode -eq 0) {
            # Delete + purge any Key Vaults first so their (soft-deleted) names are freed for re-deploys.
            $vaults = Invoke-Az -Arguments @(
                'keyvault', 'list',
                '--resource-group', $target.ResourceGroup,
                '--query', '[].name',
                '--output', 'tsv'
            ) -AllowFailure
            $vaultNames = @($vaults.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
            foreach ($vault in $vaultNames) {
                Write-Host "  Deleting + purging Key Vault $vault"
                Invoke-Az -Arguments @('keyvault', 'delete', '--name', $vault, '--output', 'none') -AllowFailure | Out-Null
                Invoke-Az -Arguments @('keyvault', 'purge', '--name', $vault, '--no-wait', '--output', 'none') -AllowFailure | Out-Null
                $vaultPurged++
            }

            Invoke-Az -Arguments @('group', 'delete', '--name', $target.ResourceGroup, '--yes', '--no-wait', '--output', 'none') | Out-Null
            $rgDeleteStarted++
        }
        else {
            Write-Host '  Resource group not found. Skipping.'
            $rgMissing++
        }

        if ($DeleteUsers) {
            Write-Host "Deleting user $($target.UserPrincipal)"
            $user = Invoke-Az -Arguments @('ad', 'user', 'show', '--id', $target.UserPrincipal, '--output', 'none') -AllowFailure
            if ($user.ExitCode -eq 0) {
                Invoke-Az -Arguments @('ad', 'user', 'delete', '--id', $target.UserPrincipal, '--output', 'none') | Out-Null
                $userDeleted++
            }
            else {
                Write-Host '  User not found. Skipping.'
                $userMissing++
            }
        }
    }

    Write-Host 'Cleanup summary:'
    Write-Host "  Resource group deletes started: $rgDeleteStarted"
    Write-Host "  Resource groups missing/skipped: $rgMissing"
    Write-Host "  Key Vaults deleted + purged: $vaultPurged"
    if ($DeleteUsers) {
        Write-Host "  Users deleted: $userDeleted"
        Write-Host "  Users missing/skipped: $userMissing"
    }

    # The shared staging resource group (rg-<prefix>-staging) holds the storage
    # account used to deliver the source-VM setup script. Remove it on a full
    # teardown (-All) or when -IncludeStaging is requested.
    if ($All -or $IncludeStaging) {
        $stagingRg = "rg-$Prefix-staging"
        $stagingGroup = Invoke-Az -Arguments @('group', 'show', '--name', $stagingRg, '--output', 'none') -AllowFailure
        if ($stagingGroup.ExitCode -eq 0) {
            Write-Host "Deleting staging resource group $stagingRg"
            Invoke-Az -Arguments @('group', 'delete', '--name', $stagingRg, '--yes', '--no-wait', '--output', 'none') | Out-Null
        }
        else {
            Write-Host "Staging resource group $stagingRg not found. Skipping."
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
