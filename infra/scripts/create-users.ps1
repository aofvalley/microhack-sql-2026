#requires -Version 7.0
[CmdletBinding()]
param(
    [int]$UserCount = 30,
    [int]$StartIndex = 1,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantDomain,
    [string]$Prefix = 'mh',
    [string]$Password,
    [string]$InitialPassword = 'Temporal01!',
    [string]$SubscriptionId,
    [switch]$AssignRbac
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
        $redactedArgs = New-Object System.Collections.Generic.List[string]
        $redactNext = $false
        foreach ($argument in $Arguments) {
            if ($redactNext) {
                $redactedArgs.Add('***') | Out-Null
                $redactNext = $false
                continue
            }
            if ($argument -eq '--password') {
                $redactedArgs.Add($argument) | Out-Null
                $redactNext = $true
                continue
            }
            $redactedArgs.Add($argument) | Out-Null
        }
        throw "az $($redactedArgs -join ' ') failed with exit code $exitCode. $($output -join [Environment]::NewLine)"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

function Get-UserIndexText {
    param([int]$Index)
    $Index.ToString('00')
}

$script:deployerObjectId = $null
function Get-DeployerObjectId {
    if ($null -ne $script:deployerObjectId) { return $script:deployerObjectId }
    $result = Invoke-Az -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv') -AllowFailure
    $script:deployerObjectId = if ($result.ExitCode -eq 0) { ($result.Output -join '').Trim() } else { '' }
    return $script:deployerObjectId
}

# Stores the student's Entra ID sign-in credentials in their per-user Key Vault so the vault
# holds every credential the student needs (portal/VM sign-in, VM local admin, and SQL logins).
# Secrets are set on the data plane, so the deployer is granted Key Vault Secrets Officer first.
function Set-StudentCredentialSecrets {
    param(
        [Parameter(Mandatory = $true)][string]$ResourceGroup,
        [Parameter(Mandatory = $true)][string]$Upn,
        [Parameter(Mandatory = $true)][string]$Password
    )

    try {
        $vaultLookup = Invoke-Az -Arguments @(
            'keyvault', 'list', '--resource-group', $ResourceGroup, '--query', '[0].name', '--output', 'tsv'
        ) -AllowFailure
        $vaultName = ($vaultLookup.Output -join '').Trim()
        if ([string]::IsNullOrWhiteSpace($vaultName)) {
            Write-Warning "  No Key Vault found in $ResourceGroup; skipping student credential storage."
            return
        }

        $deployerId = Get-DeployerObjectId
        if (-not [string]::IsNullOrWhiteSpace($deployerId)) {
            $vaultIdLookup = Invoke-Az -Arguments @('keyvault', 'show', '--name', $vaultName, '--query', 'id', '--output', 'tsv') -AllowFailure
            $vaultScope = ($vaultIdLookup.Output -join '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($vaultScope)) {
                $existingRole = Invoke-Az -Arguments @(
                    'role', 'assignment', 'list',
                    '--assignee-object-id', $deployerId,
                    '--role', 'Key Vault Secrets Officer',
                    '--scope', $vaultScope,
                    '--query', '[].id', '--output', 'tsv'
                ) -AllowFailure
                if ([string]::IsNullOrWhiteSpace(($existingRole.Output -join ''))) {
                    Write-Host "  Granting deployer 'Key Vault Secrets Officer' on $vaultName (for credential storage)."
                    Invoke-Az -Arguments @(
                        'role', 'assignment', 'create',
                        '--assignee-object-id', $deployerId,
                        '--assignee-principal-type', 'User',
                        '--role', 'Key Vault Secrets Officer',
                        '--scope', $vaultScope,
                        '--output', 'none'
                    ) -AllowFailure | Out-Null
                    Start-Sleep -Seconds 30
                }
            }
        }

        Write-Host "  Storing student credentials in Key Vault $vaultName (student-username, student-password)."
        Invoke-Az -Arguments @('keyvault', 'secret', 'set', '--vault-name', $vaultName, '--name', 'student-username', '--value', $Upn, '--output', 'none') | Out-Null
        Invoke-Az -Arguments @('keyvault', 'secret', 'set', '--vault-name', $vaultName, '--name', 'student-password', '--value', $Password, '--output', 'none') | Out-Null
    }
    catch {
        Write-Warning "  Failed to store student credentials in Key Vault: $($_.Exception.Message)"
    }
}

try {
    if ($UserCount -lt 1) { throw 'UserCount must be at least 1.' }
    if ($StartIndex -lt 1) { throw 'StartIndex must be at least 1.' }
    if ($Prefix -notmatch '^[a-z0-9]+$') { throw 'Prefix must contain only lowercase letters and numbers.' }
    if ([string]::IsNullOrWhiteSpace($Password) -and ($InitialPassword.Length -lt 8)) {
        throw 'InitialPassword must be at least 8 characters and meet Entra ID complexity (e.g. Temporal01!).'
    }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $outDir = Join-Path -Path $repoRoot -ChildPath 'out'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    if ($AssignRbac) {
        if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
            Write-Host 'SubscriptionId not supplied. Reading current Azure CLI subscription...'
            $account = Invoke-Az -Arguments @('account', 'show', '--query', 'id', '--output', 'tsv')
            $SubscriptionId = ($account.Output -join '').Trim()
        }
        if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw 'SubscriptionId is required when -AssignRbac is used.' }
        Write-Host "Setting Azure subscription to $SubscriptionId"
        Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $endIndex = $StartIndex + $UserCount - 1

    for ($index = $StartIndex; $index -le $endIndex; $index++) {
        $nn = Get-UserIndexText -Index $index
        $upn = "${Prefix}user$nn@$TenantDomain"
        $displayName = "MicroHack User $nn"
        $resourceGroup = "rg-$Prefix-user$nn"
        $createdPassword = $null

        Write-Host "[$index/$endIndex] Processing $upn"
        $existing = Invoke-Az -Arguments @('ad', 'user', 'show', '--id', $upn, '--output', 'json') -AllowFailure

        if ($existing.ExitCode -eq 0) {
            Write-Host "  User exists. Skipping create."
            $user = $existing.Output -join [Environment]::NewLine | ConvertFrom-Json
        }
        else {
            $createdPassword = if ([string]::IsNullOrWhiteSpace($Password)) { $InitialPassword } else { $Password }
            Write-Host "  Creating user with temporary password (change required at first sign-in)."
            $created = Invoke-Az -Arguments @(
                'ad', 'user', 'create',
                '--user-principal-name', $upn,
                '--display-name', $displayName,
                '--password', $createdPassword,
                '--force-change-password-next-sign-in', 'true',
                '--output', 'json'
            )
            $user = $created.Output -join [Environment]::NewLine | ConvertFrom-Json
        }

        if ($AssignRbac) {
            $scope = "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup"
            foreach ($role in @('Contributor', 'Key Vault Secrets User', 'Virtual Machine Administrator Login')) {
                Write-Host "  Ensuring role '$role' on $resourceGroup"
                $assignment = Invoke-Az -Arguments @(
                    'role', 'assignment', 'list',
                    '--assignee-object-id', $user.id,
                    '--role', $role,
                    '--scope', $scope,
                    '--query', '[].id',
                    '--output', 'tsv'
                ) -AllowFailure

                if ($assignment.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace(($assignment.Output -join ''))) {
                    Write-Host '    Assignment exists. Skipping.'
                    continue
                }

                Invoke-Az -Arguments @(
                    'role', 'assignment', 'create',
                    '--assignee-object-id', $user.id,
                    '--assignee-principal-type', 'User',
                    '--role', $role,
                    '--scope', $scope,
                    '--output', 'none'
                ) | Out-Null
            }
        }

        if ($AssignRbac -and -not [string]::IsNullOrWhiteSpace($createdPassword)) {
            Set-StudentCredentialSecrets -ResourceGroup $resourceGroup -Upn $upn -Password $createdPassword
        }
        elseif ($AssignRbac) {
            Write-Host "  User already existed; password unknown, student-* secrets not refreshed."
        }

        $rows.Add([pscustomobject]@{
            index             = $index
            userPrincipalName = $upn
            displayName       = $displayName
            password          = if ($createdPassword) { $createdPassword } else { '' }
            resourceGroup     = $resourceGroup
        }) | Out-Null
    }

    $csvPath = Join-Path -Path $outDir -ChildPath 'users.csv'
    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
    Write-Host "User CSV written to $csvPath"
    Write-Host 'Existing users were not reset; their password column is blank.'
}
catch {
    Write-Error $_
    exit 1
}
