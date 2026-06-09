#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
    [string]$TenantId,
    [int]$UserCount = 30,
    [int]$StartIndex = 1,
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
    [string]$StagingStorageAccount,
    [switch]$CreateUsers,
    [switch]$WhatIf,
    [switch]$SkipUsers,
    [switch]$SecurityControlIgnore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function New-StrongPassword {
    param([int]$Length = 20)

    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $digits = '23456789'.ToCharArray()
    # Exclude cmd.exe metacharacters (& | < > ^ %); az is az.cmd on Windows and
    # re-parses inline arguments through cmd.exe. VM/SQL passwords flow through a
    # parameters file, but create-users.ps1 passes the password inline to az.
    $special = '!#$*+-=?@_'.ToCharArray()
    $all = $upper + $lower + $digits + $special
    $chars = @(
        $upper | Get-Random
        $lower | Get-Random
        $digits | Get-Random
        $special | Get-Random
    )
    for ($i = $chars.Count; $i -lt $Length; $i++) { $chars += ($all | Get-Random) }
    -join ($chars | Sort-Object { Get-Random })
}

function ConvertTo-PlainText {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [securestring]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $text
}

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
        foreach ($argument in $Arguments) {
            if ($argument -match '^(vmAdminPassword|sqlAdminPassword)=') {
                $redactedArgs.Add(($argument -replace '=.*$', '=***')) | Out-Null
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

function Get-TenantDomain {
    Write-Host 'Discovering default tenant domain from Microsoft Graph...'
    $domain = Invoke-Az -Arguments @(
        'rest', '--method', 'get',
        '--url', 'https://graph.microsoft.com/v1.0/domains',
        '--query', 'value[?isDefault].id | [0]',
        '--output', 'tsv'
    )
    $value = ($domain.Output -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'Could not discover default tenant domain. Run create-users.ps1 manually with -TenantDomain.' }
    $value
}

function Get-CurrentPrincipal {
    # Returns the deploying principal's object id + type so we can grant it the
    # data-plane role needed for a user-delegation SAS. Works for both an
    # interactive user and a GitHub Actions service principal.
    $userType = (((Invoke-Az -Arguments @('account', 'show', '--query', 'user.type', '--output', 'tsv')).Output) -join '').Trim()
    if ($userType -eq 'servicePrincipal') {
        $appId = (((Invoke-Az -Arguments @('account', 'show', '--query', 'user.name', '--output', 'tsv')).Output) -join '').Trim()
        $oid = (((Invoke-Az -Arguments @('ad', 'sp', 'show', '--id', $appId, '--query', 'id', '--output', 'tsv')).Output) -join '').Trim()
        return [pscustomobject]@{ ObjectId = $oid; PrincipalType = 'ServicePrincipal' }
    }
    $oid = (((Invoke-Az -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv')).Output) -join '').Trim()
    return [pscustomobject]@{ ObjectId = $oid; PrincipalType = 'User' }
}

function Publish-SetupScriptToStaging {
    # The infra repo is PRIVATE, so the source-VM CustomScriptExtension cannot
    # download setup-source-vm.ps1 from raw.githubusercontent.com (404). Instead
    # we stage the local copy in a storage account and hand the CSE a short-lived
    # Azure AD user-delegation SAS URL. User-delegation SAS works even under the
    # org policy that disables shared-key auth on storage accounts.
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Location,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][string]$SubscriptionId,
        [string]$StorageAccountName
    )

    $stagingRg = "rg-$Prefix-staging"
    if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
        # Deterministic per-subscription name so repeated deploy/add-user runs
        # reuse one staging account instead of proliferating them.
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SubscriptionId)) }
        finally { $sha.Dispose() }
        $suffix = (-join ($hash | ForEach-Object { $_.ToString('x2') })).Substring(0, 8)
        $StorageAccountName = "$($Prefix)stg$suffix"
    }
    if ($StorageAccountName.Length -gt 24) { $StorageAccountName = $StorageAccountName.Substring(0, 24) }

    Write-Host "Ensuring staging resource group $stagingRg"
    Invoke-Az -Arguments @('group', 'create', '--name', $stagingRg, '--location', $Location) | Out-Null

    $showExisting = Invoke-Az -Arguments @('storage', 'account', 'show', '--resource-group', $stagingRg, '--name', $StorageAccountName, '--query', 'name', '--output', 'tsv') -AllowFailure
    if ($showExisting.ExitCode -ne 0) {
        Write-Host "Creating staging storage account $StorageAccountName"
        Invoke-Az -Arguments @(
            'storage', 'account', 'create',
            '--resource-group', $stagingRg,
            '--name', $StorageAccountName,
            '--location', $Location,
            '--sku', 'Standard_LRS',
            '--kind', 'StorageV2',
            '--min-tls-version', 'TLS1_2',
            '--allow-shared-key-access', 'false',
            '--allow-blob-public-access', 'false'
        ) | Out-Null
    }

    $saId = (((Invoke-Az -Arguments @('storage', 'account', 'show', '--resource-group', $stagingRg, '--name', $StorageAccountName, '--query', 'id', '--output', 'tsv')).Output) -join '').Trim()

    $principal = Get-CurrentPrincipal
    Write-Host "Granting Storage Blob Data Contributor to $($principal.PrincipalType) $($principal.ObjectId)"
    Invoke-Az -Arguments @(
        'role', 'assignment', 'create',
        '--assignee-object-id', $principal.ObjectId,
        '--assignee-principal-type', $principal.PrincipalType,
        '--role', 'Storage Blob Data Contributor',
        '--scope', $saId
    ) -AllowFailure | Out-Null

    # RBAC propagation to the storage data plane is eventually consistent and can
    # take a few minutes, sometimes succeeding for one call but not the next. Retry
    # the whole upload sequence (container create + blob upload) until it sticks.
    $expiry = (Get-Date).ToUniversalTime().AddHours(24).ToString('yyyy-MM-ddTHH:mmZ')
    $uploaded = $false
    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $c = Invoke-Az -Arguments @('storage', 'container', 'create', '--account-name', $StorageAccountName, '--auth-mode', 'login', '--name', 'scripts') -AllowFailure
        if ($c.ExitCode -eq 0) {
            $u = Invoke-Az -Arguments @('storage', 'blob', 'upload', '--account-name', $StorageAccountName, '--auth-mode', 'login', '--container-name', 'scripts', '--name', 'setup-source-vm.ps1', '--file', $ScriptPath, '--overwrite') -AllowFailure
            if ($u.ExitCode -eq 0) { $uploaded = $true; break }
        }
        Write-Host "  Waiting for Storage Blob Data Contributor to propagate (attempt $attempt/15)..."
        Start-Sleep -Seconds 20
    }
    if (-not $uploaded) { throw 'Storage Blob Data Contributor did not propagate in time; cannot stage the setup script.' }

    # generate-sas with --as-user also needs the data-plane role (user-delegation key); retry too.
    $sasUrl = ''
    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $s = Invoke-Az -Arguments @(
            'storage', 'blob', 'generate-sas',
            '--account-name', $StorageAccountName,
            '--auth-mode', 'login', '--as-user',
            '--container-name', 'scripts',
            '--name', 'setup-source-vm.ps1',
            '--permissions', 'r',
            '--expiry', $expiry,
            '--https-only', '--full-uri',
            '--output', 'tsv'
        ) -AllowFailure
        if ($s.ExitCode -eq 0) {
            $sasUrl = (($s.Output) -join '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($sasUrl)) { break }
        }
        Write-Host "  Waiting to generate user-delegation SAS (attempt $attempt/15)..."
        Start-Sleep -Seconds 20
    }
    if ([string]::IsNullOrWhiteSpace($sasUrl)) { throw 'Failed to generate a user-delegation SAS for the setup script.' }
    Write-Host 'Staged source-VM setup script; user-delegation SAS valid for 24h.'
    return $sasUrl
}

function Add-GuideUserSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [object]$User,
        [int]$FallbackIndex,
        [string]$VmAdminUser,
        [string]$VmAdminPasswordPlain,
        [string]$SqlAdminUser,
        [string]$SqlAdminPasswordPlain
    )

    $idx = if ($User.PSObject.Properties.Name -contains 'index') { [int]$User.index } else { $FallbackIndex }
    $nn = $idx.ToString('00')
    $rg = if ($User.PSObject.Properties.Name -contains 'resourceGroup') { $User.resourceGroup } else { "rg-$Prefix-user$nn" }
    $vm = if ($User.PSObject.Properties.Name -contains 'vmName') { $User.vmName } else { '' }
    $bastion = if ($User.PSObject.Properties.Name -contains 'bastionName') { $User.bastionName } else { '' }
    $sqlServer = if ($User.PSObject.Properties.Name -contains 'sqlServerFqdn') { $User.sqlServerFqdn } else { '' }
    $sqlMi = if ($User.PSObject.Properties.Name -contains 'sqlMiFqdn') { $User.sqlMiFqdn } else { '' }
    $keyVault = if ($User.PSObject.Properties.Name -contains 'keyVaultName') { $User.keyVaultName } else { '' }

    $Lines.Add("## User $nn") | Out-Null
    $Lines.Add('') | Out-Null
    $Lines.Add("- Resource group: ``$rg``") | Out-Null
    $Lines.Add("- VM name: ``$vm``") | Out-Null
    $Lines.Add("- Bastion name: ``$bastion``") | Out-Null
    $Lines.Add("- SQL Server FQDN: ``$sqlServer``") | Out-Null
    $Lines.Add("- SQL MI FQDN: ``$sqlMi``") | Out-Null
    $Lines.Add("- Key Vault: ``$keyVault`` (secrets: student-username, student-password, vm-admin-username, vm-admin-password, sql-admin-login, sql-admin-password)") | Out-Null
    $Lines.Add("- VM admin username: ``$VmAdminUser``") | Out-Null
    $Lines.Add("- VM admin password: ``$VmAdminPasswordPlain``") | Out-Null
    $Lines.Add("- SQL admin login: ``$SqlAdminUser``") | Out-Null
    $Lines.Add("- SQL admin password: ``$SqlAdminPasswordPlain``") | Out-Null
    $Lines.Add('') | Out-Null
    $Lines.Add('Bastion connection: Azure Portal > resource group > VM > Connect > Bastion, then sign in with the VM admin credentials above or the assigned lab user.') | Out-Null
    $Lines.Add('') | Out-Null
}

$transcriptStarted = $false
try {
    if ($UserCount -lt 1) { throw 'UserCount must be at least 1.' }
    if ($StartIndex -lt 1) { throw 'StartIndex must be at least 1.' }
    if ($Prefix -notmatch '^[a-z0-9]+$') { throw 'Prefix must contain only lowercase letters and numbers.' }
    if ($Prefix.Length -gt 8) { throw 'Prefix must be 8 characters or fewer (matches bicep namePrefix maxLength).' }
    if (-not [string]::IsNullOrWhiteSpace($StagingStorageAccount) -and $StagingStorageAccount -notmatch '^[a-z0-9]{3,24}$') {
        throw 'StagingStorageAccount must be 3-24 lowercase letters/numbers.'
    }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found in PATH.' }

    $trueValues = @('true', '$true', '1', 'yes')
    $deploySqlMiBool = $trueValues -contains $DeploySqlMi.ToLowerInvariant()
    $deploySourceVmBool = $trueValues -contains $DeploySourceVm.ToLowerInvariant()

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $outDir = Join-Path -Path $repoRoot -ChildPath 'out'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path -Path $outDir -ChildPath "deploy-$timestamp.log"
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $templateFile = Join-Path -Path $repoRoot -ChildPath 'bicep\main.bicep'
    if (-not (Test-Path -Path $templateFile)) { throw "Template file not found: $templateFile" }

    $vmPasswordPlain = ConvertTo-PlainText -Value $VmAdminPassword
    if ([string]::IsNullOrWhiteSpace($vmPasswordPlain)) {
        $vmPasswordPlain = New-StrongPassword
        Write-Host 'Generated VM admin password.'
    }

    $sqlPasswordPlain = ConvertTo-PlainText -Value $SqlAdminPassword
    if ([string]::IsNullOrWhiteSpace($sqlPasswordPlain)) {
        $sqlPasswordPlain = New-StrongPassword
        Write-Host 'Generated SQL admin password.'
    }

    Write-Host "Setting Azure subscription to $SubscriptionId"
    Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

    # Register the subscription-level resource providers the lab needs. Students only get
    # Contributor on their resource group, so they cannot register providers themselves —
    # in particular Microsoft.DataMigration is required for the Challenge 2 DMS migration.
    $requiredProviders = @(
        'Microsoft.DataMigration',
        'Microsoft.Sql',
        'Microsoft.KeyVault',
        'Microsoft.Compute',
        'Microsoft.Network'
    )
    foreach ($provider in $requiredProviders) {
        $state = (Invoke-Az -Arguments @('provider', 'show', '--namespace', $provider, '--query', 'registrationState', '--output', 'tsv') -AllowFailure).Output -join ''
        if ($state.Trim() -ne 'Registered') {
            Write-Host "Registering resource provider $provider (was '$($state.Trim())')"
            Invoke-Az -Arguments @('provider', 'register', '--namespace', $provider) -AllowFailure | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        $currentTenant = Invoke-Az -Arguments @('account', 'show', '--query', 'tenantId', '--output', 'tsv')
        $currentTenantId = ($currentTenant.Output -join '').Trim()
        if ($currentTenantId -ne $TenantId) {
            Write-Host "Warning: current Azure CLI tenant is $currentTenantId, expected $TenantId. Continuing with selected subscription."
        }
    }

    $deploymentName = "microhack-sql-$timestamp"

    # Deliver the source-VM setup script to the CustomScriptExtension. The repo is
    # private, so a raw.githubusercontent.com URL would 404. Stage the local copy
    # and use a user-delegation SAS unless the caller supplied an explicit URI.
    $effectiveSetupUri = $SetupScriptUri
    if ($deploySourceVmBool -and -not $WhatIf) {
        if ([string]::IsNullOrWhiteSpace($SetupScriptUri)) {
            $setupScriptPath = Join-Path -Path $repoRoot -ChildPath 'bicep\scripts\setup-source-vm.ps1'
            if (-not (Test-Path -Path $setupScriptPath)) { throw "Setup script not found: $setupScriptPath" }
            Write-Host 'Staging source-VM setup script (private-repo safe delivery via user-delegation SAS)...'
            $effectiveSetupUri = Publish-SetupScriptToStaging -ScriptPath $setupScriptPath -Location $Location -Prefix $Prefix -SubscriptionId $SubscriptionId -StorageAccountName $StagingStorageAccount
        }
        else {
            Write-Host 'Using the provided SetupScriptUri override for the source VM.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($effectiveSetupUri)) {
        # main.bicep requires the parameter even when the source VM is skipped.
        $effectiveSetupUri = 'https://example.invalid/setup-source-vm.ps1'
    }

    # Pass ALL parameters via a parameters file. On Windows, az is a batch
    # wrapper (az.cmd) routed through cmd.exe, which re-parses inline values and
    # mangles special characters (e.g. & | < > ^) in generated passwords. Using
    # an @file avoids all shell quoting/escaping issues.
    $paramValues = @{
        userCount      = @{ value = $UserCount }
        startUserIndex = @{ value = $StartIndex }
        location       = @{ value = $Location }
        namePrefix     = @{ value = $Prefix }
        vmAdminUsername = @{ value = 'mhadmin' }
        vmAdminPassword = @{ value = $vmPasswordPlain }
        sqlAdminLogin  = @{ value = 'sqladmin' }
        sqlAdminPassword = @{ value = $sqlPasswordPlain }
        deploySourceVm = @{ value = $deploySourceVmBool }
        deploySqlMi    = @{ value = $deploySqlMiBool }
        vmSize         = @{ value = 'Standard_D4s_v5' }
        autoShutdownTime = @{ value = '1900' }
        setupScriptUri = @{ value = $effectiveSetupUri }
    }

    if ($SecurityControlIgnore) {
        # Tags SQL Server / SQL MI with SecurityControl=Ignore to satisfy MCAPS
        # governance deny policies when testing in a Microsoft-internal tenant.
        $paramValues['resourceTags'] = @{ value = @{ SecurityControl = 'Ignore' } }
    }

    $paramFile = Join-Path -Path $outDir -ChildPath "deploy-params-$timestamp.json"
    $paramContent = @{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters     = $paramValues
    } | ConvertTo-Json -Depth 8
    Set-Content -Path $paramFile -Value $paramContent -Encoding utf8

    $commonArgs = @(
        '--name', $deploymentName,
        '--location', $Location,
        '--template-file', $templateFile,
        '--parameters', "@$paramFile",
        '--output', 'json'
    )

    $jsonPath = Join-Path -Path $outDir -ChildPath "deployment-$timestamp.json"

    if ($WhatIf) {
        Write-Host "Running subscription what-if deployment $deploymentName"
        $whatIfResult = Invoke-Az -Arguments (@('deployment', 'sub', 'what-if') + $commonArgs)
        $whatIfResult.Output | Set-Content -Path $jsonPath -Encoding utf8
        Write-Host "What-if output written to $jsonPath"
        return
    }

    Write-Host "Running subscription deployment $deploymentName"
    $deployment = Invoke-Az -Arguments (@('deployment', 'sub', 'create') + $commonArgs)
    $deployment.Output | Set-Content -Path $jsonPath -Encoding utf8
    Write-Host "Deployment JSON written to $jsonPath"

    $deploymentObject = $deployment.Output -join [Environment]::NewLine | ConvertFrom-Json
    $users = @()
    $outputNames = @()
    if ($null -ne $deploymentObject.properties -and $null -ne $deploymentObject.properties.outputs) {
        $outputNames = @($deploymentObject.properties.outputs.PSObject.Properties.Name)
    }
    if ($outputNames -contains 'users') {
        $users = @($deploymentObject.properties.outputs.users.value)
    }
    else {
        Write-Host 'Warning: deployment output users was not found. Connection guide will use generated names only.'
        for ($index = $StartIndex; $index -le ($StartIndex + $UserCount - 1); $index++) {
            $nn = $index.ToString('00')
            $users += [pscustomobject]@{
                index          = $index
                resourceGroup  = "rg-$Prefix-user$nn"
                sqlServerFqdn  = ''
                sqlMiFqdn      = ''
                vmName         = ''
                bastionName    = ''
            }
        }
    }

    $guidePath = Join-Path -Path $outDir -ChildPath 'connection-guide.md'
    $guide = [System.Collections.Generic.List[string]]::new()
    $guide.Add('# MicroHack SQL 2026 Connection Guide') | Out-Null
    $guide.Add('') | Out-Null
    $guide.Add("Deployment: ``$deploymentName``") | Out-Null
    $guide.Add("Location: ``$Location``") | Out-Null
    $guide.Add('') | Out-Null
    $guide.Add('> This facilitator guide intentionally contains lab credentials. Store and share it accordingly.') | Out-Null
    $guide.Add('') | Out-Null

    $fallback = $StartIndex
    foreach ($user in $users) {
        Add-GuideUserSection -Lines $guide -User $user -FallbackIndex $fallback -VmAdminUser 'mhadmin' -VmAdminPasswordPlain $vmPasswordPlain -SqlAdminUser 'sqladmin' -SqlAdminPasswordPlain $sqlPasswordPlain
        $fallback++
    }
    $guide | Set-Content -Path $guidePath -Encoding utf8
    Write-Host "Connection guide written to $guidePath"

    if ($CreateUsers -and -not $SkipUsers) {
        $tenantDomain = Get-TenantDomain
        $createUsersScript = Join-Path -Path $PSScriptRoot -ChildPath 'create-users.ps1'
        Write-Host "Creating/assigning Entra lab users in $tenantDomain"
        & $createUsersScript -UserCount $UserCount -StartIndex $StartIndex -TenantDomain $tenantDomain -Prefix $Prefix -InitialPassword $InitialPassword -SubscriptionId $SubscriptionId -AssignRbac
        if ($LASTEXITCODE -ne 0) { throw 'create-users.ps1 failed.' }
    }
    elseif ($CreateUsers -and $SkipUsers) {
        Write-Host 'CreateUsers and SkipUsers were both specified. Skipping user creation.'
    }

    Write-Host 'Deployment orchestration completed successfully.'
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}
