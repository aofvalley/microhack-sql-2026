#Requires -Version 7.0
<#
    MicroHack SQL Modernization 2026 - Workshop Infrastructure Deployment
    =====================================================================
    Deploys the full multi-team lab environment:
      - VNet with 4 subnets + NSGs + Azure Bastion
      - 2 shared SQL Server 2019 VMs (simulating SQL 2012/2016 via compat mode)
      - N JumpBox VMs (one per team), tools installed via RunCommand
      - Per-team databases, SQL logins, dirty workload
      - Optional SQL Managed Instance
      - Auto-shutdown schedule on all VMs
      - Optional Entra ID RBAC assignment from CSV

    Usage:
        .\deploy.ps1 -SubscriptionId <sub> -TenantId <tid>
        .\deploy.ps1 -SubscriptionId <sub> -TenantId <tid> -TeamCount 17 -DeploySQLMI $true
        .\deploy.ps1 -SubscriptionId <sub> -TenantId <tid> -UsersCSV .\users.csv -DryRun

    Idempotent: safe to re-run; existing resources are skipped.
    Output: scripts/out/team-credentials.csv and scripts/out/connection-guide.md
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive workshop script uses colored console output.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'AdminPassword', Justification = 'Lab credentials are passed to Azure CLI and emitted to the generated team handoff CSV.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', '', Justification = 'Analyzer misidentifies generated Markdown table text as commands.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '', Justification = 'Start-Job script block receives values through param and ArgumentList.')]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $TenantId,
    [int]    $TeamCount        = 1,
    [string] $Location         = 'westeurope',
    [string] $ResourceGroup    = 'rg-sqlhack-microhack-2026',
    [string] $Prefix           = 'sqlhack',
    [string] $AdminUsername    = 'demouser',
    [string] $AdminPassword    = '',
    [bool]   $DeploySQLMI      = $false,
    [string] $UsersCSV         = '',
    [string] $AutoShutdownTime = '1900',   # HHmm UTC; empty string disables
    [switch] $DryRun
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
[void]$TenantId
[void]$UsersCSV
[void]$DryRun

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

function Write-Step  { param([string]$msg) Write-Host "`n>  $msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$msg) Write-Host "   OK $msg" -ForegroundColor Green }
function Write-Info  { param([string]$msg) Write-Host "   i $msg" -ForegroundColor Gray }
function Write-Warn  { param([string]$msg) Write-Host "   ! $msg" -ForegroundColor Yellow }

function Get-RandomSuffix {
    -join ((1..6) | ForEach-Object { [char](Get-Random -Minimum 97 -Maximum 123) })
}

function Get-SqlPassword {
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower   = 'abcdefghijklmnopqrstuvwxyz'
    $digits  = '0123456789'
    $special = '!@#$'
    $all     = $upper + $lower + $digits + $special
    return  ($upper[(Get-Random -Min 0 -Max $upper.Length)] ).ToString() +
            ($digits[(Get-Random -Min 0 -Max $digits.Length)]).ToString() +
            ($special[(Get-Random -Min 0 -Max $special.Length)]).ToString() +
            (-join ((1..9) | ForEach-Object { $all[(Get-Random -Min 0 -Max $all.Length)] }))
}

function Invoke-AzCmd {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$CmdArgs)
    if ($DryRun) { Write-Info "[DRY RUN] az $($CmdArgs -join ' ')"; return $null }
    $out = & az @CmdArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $head = if ($CmdArgs.Count -ge 3) { $CmdArgs[0..2] -join ' ' } else { $CmdArgs -join ' ' }
        throw "az $head failed: $out"
    }
    return $out
}

function Test-AzResourcePresence {
    param([string[]]$ShowArgs)
    az @ShowArgs 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
Write-Step "Preflight"

az account set --subscription $SubscriptionId --only-show-errors
$subInfo = az account show | ConvertFrom-Json
Write-OK "Subscription: $($subInfo.name) ($($subInfo.id))"

if ($TeamCount -lt 1 -or $TeamCount -gt 50) { throw "TeamCount must be 1-50 (got $TeamCount)" }

if (-not $AdminPassword) {
    $AdminPassword = "Demo@$(Get-SqlPassword)!"
    Write-Info "Admin password auto-generated (will be saved to out/team-credentials.csv)"
}

# Validate optional users CSV
$userAssignments = @()
if ($UsersCSV -and (Test-Path $UsersCSV)) {
    $userAssignments = Import-Csv -Path $UsersCSV
    foreach ($col in @('userPrincipalName', 'teamNumber')) {
        if ($col -notin ($userAssignments | Get-Member -MemberType NoteProperty).Name) {
            throw "users.csv missing column: $col"
        }
    }
    Write-OK "Users CSV: $($userAssignments.Count) entries loaded"
}

az extension add --name sql-vm --upgrade --only-show-errors 2>$null | Out-Null
az extension add --name bastion --upgrade --only-show-errors 2>$null | Out-Null
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors 2>$null | Out-Null

$outDir  = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logFile = Join-Path $outDir "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -Append | Out-Null

if ($DryRun) {
    Write-Host "`n[DRY RUN] Would deploy:" -ForegroundColor Yellow
    Write-Host "  Resource group  : $ResourceGroup ($Location)"
    Write-Host "  Teams           : $TeamCount"
    Write-Host "  SQL MI          : $DeploySQLMI"
    Write-Host "  Auto-shutdown   : ${AutoShutdownTime} UTC"
    Write-Host "  Entra RBAC users: $($userAssignments.Count)"
    Stop-Transcript | Out-Null
    exit 0
}

# Pre-generate per-team SQL passwords
$teamPasswords = @{}
for ($i = 1; $i -le $TeamCount; $i++) {
    $teamPasswords[('{0:D2}' -f $i)] = Get-SqlPassword
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
Write-Step "Resource Group"

if (-not (Test-AzResourcePresence 'group', 'show', '--name', $ResourceGroup)) {
    Invoke-AzCmd 'group', 'create', '--name', $ResourceGroup, '--location', $Location,
        '--tags', 'workshop=microhack-sql-2026' | Out-Null
    Write-OK "Created: $ResourceGroup"
} else {
    Write-OK "Existing: $ResourceGroup"
}

# -----------------------------------------------------------------------------
# Networking: VNet, Subnets, NSGs, Bastion
# -----------------------------------------------------------------------------
Write-Step "Networking"

$vnetName = "$Prefix-vnet-shared"

if (-not (Test-AzResourcePresence 'network', 'vnet', 'show', '--resource-group', $ResourceGroup, '--name', $vnetName)) {
    Invoke-AzCmd 'network', 'vnet', 'create',
        '--resource-group', $ResourceGroup, '--name', $vnetName,
        '--location', $Location, '--address-prefix', '10.0.0.0/16' | Out-Null
    Write-OK "VNet: $vnetName"

    $subnets = @(
        @{ name='snet-mi';            prefix='10.0.1.0/24'; deleg='Microsoft.Sql/managedInstances' },
        @{ name='snet-mgmt';          prefix='10.0.2.0/24'; deleg='' },
        @{ name='snet-jumpboxes';     prefix='10.0.3.0/24'; deleg='' },
        @{ name='AzureBastionSubnet'; prefix='10.0.4.0/26'; deleg='' }
    )
    foreach ($sn in $subnets) {
        $snArgs = 'network', 'vnet', 'subnet', 'create',
            '--resource-group', $ResourceGroup, '--vnet-name', $vnetName,
            '--name', $sn.name, '--address-prefixes', $sn.prefix
        if ($sn.deleg) { $snArgs += '--delegations', $sn.deleg }
        Invoke-AzCmd @snArgs | Out-Null
        Write-OK "Subnet: $($sn.name)"
    }
} else {
    Write-OK "VNet exists: $vnetName"
}

# NSG - Management subnet (deny inbound RDP from internet)
$nsgMgmt = "$Prefix-nsg-mgmt"
if (-not (Test-AzResourcePresence 'network', 'nsg', 'show', '--resource-group', $ResourceGroup, '--name', $nsgMgmt)) {
    Invoke-AzCmd 'network', 'nsg', 'create', '--resource-group', $ResourceGroup, '--name', $nsgMgmt, '--location', $Location | Out-Null
    Invoke-AzCmd 'network', 'nsg', 'rule', 'create',
        '--resource-group', $ResourceGroup, '--nsg-name', $nsgMgmt,
        '--name', 'DenyRDPInternet', '--priority', '200', '--direction', 'Inbound',
        '--access', 'Deny', '--protocol', 'Tcp', '--destination-port-ranges', '3389',
        '--source-address-prefixes', 'Internet' | Out-Null
    Invoke-AzCmd 'network', 'vnet', 'subnet', 'update',
        '--resource-group', $ResourceGroup, '--vnet-name', $vnetName,
        '--name', 'snet-mgmt', '--network-security-group', $nsgMgmt | Out-Null
    Write-OK "NSG: $nsgMgmt -> snet-mgmt"
}

# NSG - JumpBox subnet
$nsgJb = "$Prefix-nsg-jumpboxes"
if (-not (Test-AzResourcePresence 'network', 'nsg', 'show', '--resource-group', $ResourceGroup, '--name', $nsgJb)) {
    Invoke-AzCmd 'network', 'nsg', 'create', '--resource-group', $ResourceGroup, '--name', $nsgJb, '--location', $Location | Out-Null
    Invoke-AzCmd 'network', 'nsg', 'rule', 'create',
        '--resource-group', $ResourceGroup, '--nsg-name', $nsgJb,
        '--name', 'DenyRDPInternet', '--priority', '200', '--direction', 'Inbound',
        '--access', 'Deny', '--protocol', 'Tcp', '--destination-port-ranges', '3389',
        '--source-address-prefixes', 'Internet' | Out-Null
    Invoke-AzCmd 'network', 'vnet', 'subnet', 'update',
        '--resource-group', $ResourceGroup, '--vnet-name', $vnetName,
        '--name', 'snet-jumpboxes', '--network-security-group', $nsgJb | Out-Null
    Write-OK "NSG: $nsgJb -> snet-jumpboxes"
}

# Azure Bastion (Basic SKU - sufficient for workshop)
$bastionName   = "$Prefix-bastion"
$bastionPipName = "$bastionName-pip"
if (-not (Test-AzResourcePresence 'network', 'bastion', 'show', '--resource-group', $ResourceGroup, '--name', $bastionName)) {
    Invoke-AzCmd 'network', 'public-ip', 'create',
        '--resource-group', $ResourceGroup, '--name', $bastionPipName,
        '--location', $Location, '--sku', 'Standard', '--allocation-method', 'Static' | Out-Null
    Invoke-AzCmd 'network', 'bastion', 'create',
        '--resource-group', $ResourceGroup, '--name', $bastionName,
        '--location', $Location, '--vnet-name', $vnetName,
        '--public-ip-address', $bastionPipName, '--sku', 'Basic' | Out-Null
    Write-OK "Bastion: $bastionName (Basic)"
} else {
    Write-OK "Bastion exists: $bastionName"
}

# -----------------------------------------------------------------------------
# Storage Account
# -----------------------------------------------------------------------------
Write-Step "Storage Account"

$existingSA = az storage account list --resource-group $ResourceGroup `
    --query "[?tags.workshop=='microhack-sql-2026'].name | [0]" -o tsv 2>$null

if ($existingSA -and $existingSA.Trim()) {
    $saName = $existingSA.Trim()
    Write-OK "Existing: $saName"
} else {
    $saName = ($Prefix -replace '-','') + 'sa' + (Get-RandomSuffix)
    Invoke-AzCmd 'storage', 'account', 'create',
        '--resource-group', $ResourceGroup, '--name', $saName,
        '--location', $Location, '--sku', 'Standard_LRS',
        '--tags', 'workshop=microhack-sql-2026' | Out-Null
    Invoke-AzCmd 'storage', 'container', 'create',
        '--account-name', $saName, '--name', 'backups', '--auth-mode', 'login' | Out-Null
    Write-OK "Created: $saName (container: backups)"
}

# -----------------------------------------------------------------------------
# SQL Legacy VMs (async)
# -----------------------------------------------------------------------------
Write-Step "SQL Legacy VMs (async)"

$sqlVmImage = 'MicrosoftSQLServer:sql2019-ws2022:sqldev-gen2:latest'
$sqlVmSize  = 'Standard_D4s_v5'

$sqlVms = @(
    @{ name="$Prefix-sql-2012"; computer='sql2012'; ip='10.0.2.4'; compat=110; tag='sql-source-a' },
    @{ name="$Prefix-sql-2016"; computer='sql2016'; ip='10.0.2.5'; compat=130; tag='sql-source-b' }
)

foreach ($vm in $sqlVms) {
    if (-not (Test-AzResourcePresence 'vm', 'show', '--resource-group', $ResourceGroup, '--name', $vm.name)) {
        $nicName = "$($vm.name)-nic"
        if (-not (Test-AzResourcePresence 'network', 'nic', 'show', '--resource-group', $ResourceGroup, '--name', $nicName)) {
            Invoke-AzCmd 'network', 'nic', 'create',
                '--resource-group', $ResourceGroup, '--name', $nicName,
                '--location', $Location,
                '--vnet-name', $vnetName, '--subnet', 'snet-mgmt',
                '--private-ip-address', $vm.ip | Out-Null
        }
        Invoke-AzCmd 'vm', 'create',
            '--resource-group', $ResourceGroup, '--name', $vm.name,
            '--location', $Location, '--image', $sqlVmImage, '--size', $sqlVmSize,
            '--computer-name', $vm.computer,
            '--admin-username', $AdminUsername, '--admin-password', $AdminPassword,
            '--nics', $nicName,
            '--os-disk-delete-option', 'delete', '--storage-sku', 'Premium_LRS',
            '--data-disk-sizes-gb', '256',
            '--tags', "workshop=microhack-sql-2026", "role=$($vm.tag)",
            '--no-wait' | Out-Null
        Write-Info "Deploying $($vm.name) @ $($vm.ip) (async)..."
    } else {
        Write-OK "Exists: $($vm.name)"
    }
}

# -----------------------------------------------------------------------------
# JumpBox VMs (async)
# -----------------------------------------------------------------------------
Write-Step "JumpBox VMs (async)"

$jbImage = 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest'
$jbSize  = 'Standard_D2s_v5'

for ($i = 1; $i -le $TeamCount; $i++) {
    $teamNum = '{0:D2}' -f $i
    $jbName  = "$Prefix-team-$teamNum"

    if (-not (Test-AzResourcePresence 'vm', 'show', '--resource-group', $ResourceGroup, '--name', $jbName)) {
        $jbNicName = "$jbName-nic"
        if (-not (Test-AzResourcePresence 'network', 'nic', 'show', '--resource-group', $ResourceGroup, '--name', $jbNicName)) {
            Invoke-AzCmd 'network', 'nic', 'create',
                '--resource-group', $ResourceGroup, '--name', $jbNicName,
                '--location', $Location,
                '--vnet-name', $vnetName, '--subnet', 'snet-jumpboxes',
                '--network-security-group', $nsgJb | Out-Null
        }
        Invoke-AzCmd 'vm', 'create',
            '--resource-group', $ResourceGroup, '--name', $jbName,
            '--location', $Location, '--image', $jbImage, '--size', $jbSize,
            '--admin-username', $AdminUsername, '--admin-password', $AdminPassword,
            '--nics', $jbNicName,
            '--tags', "workshop=microhack-sql-2026", "team=TEAM$teamNum",
            '--no-wait' | Out-Null
        Write-Info "Deploying JumpBox: $jbName (async)..."
    } else {
        Write-OK "Exists: $jbName"
    }
}

# -----------------------------------------------------------------------------
# Wait for all VMs to be running
# -----------------------------------------------------------------------------
Write-Step "Waiting for all VMs (timeout 30 min)"

$allVmNames = ($sqlVms | ForEach-Object { $_.name }) +
              (1..$TeamCount | ForEach-Object { "$Prefix-team-$('{0:D2}' -f $_)" })

foreach ($vmName in $allVmNames) {
    Write-Info "Waiting: $vmName"
    Invoke-AzCmd 'vm', 'wait', '--resource-group', $ResourceGroup, '--name', $vmName,
        '--created', '--timeout', '1800' | Out-Null
    Write-OK "Ready: $vmName"
}

# -----------------------------------------------------------------------------
# SQL IaaS Extension - enables mixed auth, private connectivity
# -----------------------------------------------------------------------------
Write-Step "SQL IaaS Extension"

foreach ($vm in $sqlVms) {
    if (-not (Test-AzResourcePresence 'sql', 'vm', 'show', '--resource-group', $ResourceGroup, '--name', $vm.name)) {
        Invoke-AzCmd 'sql', 'vm', 'create',
            '--resource-group', $ResourceGroup, '--name', $vm.name,
            '--license-type', 'PAYG', '--connectivity-type', 'PRIVATE', '--port', '1433',
            '--sql-auth-update-username', $AdminUsername,
            '--sql-auth-update-pwd', $AdminPassword | Out-Null
        Write-OK "SQL IaaS registered: $($vm.name)"
    } else {
        Write-OK "SQL IaaS exists: $($vm.name)"
    }
}

# -----------------------------------------------------------------------------
# SQL VM prerequisites (TCP/IP, SQL Agent, backup folder)
# -----------------------------------------------------------------------------
Write-Step "SQL VM prerequisites"

$prereqScript = Get-Content (Join-Path $PSScriptRoot 'cse\install-sqlvm-prereqs.ps1') -Raw

foreach ($vm in $sqlVms) {
    Write-Info "Configuring $($vm.name)..."
    Invoke-AzCmd 'vm', 'run-command', 'invoke',
        '--resource-group', $ResourceGroup, '--name', $vm.name,
        '--command-id', 'RunPowerShellScript',
        '--scripts', $prereqScript | Out-Null
    Write-OK "Prerequisites: $($vm.name)"
}

# -----------------------------------------------------------------------------
# Download sample databases onto SQL VMs
# -----------------------------------------------------------------------------
Write-Step "Downloading sample .bak files onto SQL VMs (~5-10 min each)"

$dlScript = Get-Content (Join-Path $PSScriptRoot 'sql\download-sample-dbs.ps1') -Raw

foreach ($vm in $sqlVms) {
    Write-Info "Downloading on $($vm.name)..."
    Invoke-AzCmd 'vm', 'run-command', 'invoke',
        '--resource-group', $ResourceGroup, '--name', $vm.name,
        '--command-id', 'RunPowerShellScript',
        '--scripts', $dlScript | Out-Null
    Write-OK "Downloads done: $($vm.name)"
}

# -----------------------------------------------------------------------------
# Restore per-team databases
# -----------------------------------------------------------------------------
Write-Step "Restoring per-team databases"

$setupScript = Get-Content (Join-Path $PSScriptRoot 'sql\setup-team-dbs.ps1') -Raw

foreach ($vm in $sqlVms) {
    foreach ($dbInfo in @(
        @{ db='AdventureWorks2019'; bak='AdventureWorks2019.bak' },
        @{ db='WideWorldImporters'; bak='WideWorldImporters-Full.bak' }
    )) {
        Write-Info "Restoring $($dbInfo.db) x $TeamCount teams on $($vm.name) (compat $($vm.compat))..."
        Invoke-AzCmd 'vm', 'run-command', 'invoke',
            '--resource-group', $ResourceGroup, '--name', $vm.name,
            '--command-id', 'RunPowerShellScript',
            '--scripts', $setupScript,
            '--parameters',
                "TeamCount=$TeamCount",
                "CompatLevel=$($vm.compat)",
                "SampleDb=$($dbInfo.db)",
                "BackupFile=$($dbInfo.bak)" | Out-Null
        Write-OK "Restored $($dbInfo.db) on $($vm.name)"
    }
}

# -----------------------------------------------------------------------------
# Dirty workload + team SQL logins
# -----------------------------------------------------------------------------
Write-Step "Dirty workload + team SQL logins"

$dirtySql  = Get-Content (Join-Path $PSScriptRoot 'sql\dirty-workload.sql') -Raw
$grantSql  = Get-Content (Join-Path $PSScriptRoot 'sql\grant-team-permissions.sql') -Raw

for ($i = 1; $i -le $TeamCount; $i++) {
    $teamNum    = '{0:D2}' -f $i
    $teamPrefix = "TEAM$teamNum"
    $teamLogin  = "team$teamNum"
    $teamPass   = $teamPasswords[$teamNum]

    foreach ($vm in $sqlVms) {
        # Upload dirty-workload.sql to VM, then run with sqlcmd variable substitution
        $runDirty = @"
@'
$dirtySql
'@ | Out-File 'C:\Lab\dirty-workload.sql' -Encoding UTF8 -Force
sqlcmd -S localhost -E -TrustServerCertificate -v TeamPrefix=$teamPrefix -i C:\Lab\dirty-workload.sql
"@
        Invoke-AzCmd 'vm', 'run-command', 'invoke',
            '--resource-group', $ResourceGroup, '--name', $vm.name,
            '--command-id', 'RunPowerShellScript',
            '--scripts', $runDirty | Out-Null

        # Upload grant script, run with variable substitution
        $runGrant = @"
@'
$grantSql
'@ | Out-File 'C:\Lab\grant-team.sql' -Encoding UTF8 -Force
sqlcmd -S localhost -E -TrustServerCertificate ``
    -v TeamPrefix=$teamPrefix -v TeamLogin=$teamLogin -v TeamPassword='$teamPass' ``
    -i C:\Lab\grant-team.sql
"@
        Invoke-AzCmd 'vm', 'run-command', 'invoke',
            '--resource-group', $ResourceGroup, '--name', $vm.name,
            '--command-id', 'RunPowerShellScript',
            '--scripts', $runGrant | Out-Null
    }
    Write-OK "Team ${teamNum}: login=$teamLogin configured on both SQL VMs"
}

# -----------------------------------------------------------------------------
# JumpBox tools (parallel PowerShell background jobs)
# -----------------------------------------------------------------------------
Write-Step "Installing tools on JumpBoxes (parallel - ~20 min)"

$jbToolScript = Get-Content (Join-Path $PSScriptRoot 'cse\install-jumpbox-tools.ps1') -Raw

$jobs = @()
for ($i = 1; $i -le $TeamCount; $i++) {
    $teamNum = '{0:D2}' -f $i
    $jbName  = "$Prefix-team-$teamNum"
    $jobs += Start-Job -ScriptBlock {
        param($rg, $vm, $script, $sub)
        az account set --subscription $sub 2>$null | Out-Null
        az vm run-command invoke `
            --resource-group $rg --name $vm `
            --command-id RunPowerShellScript `
            --scripts $script 2>&1
    } -ArgumentList $ResourceGroup, $jbName, $jbToolScript, $SubscriptionId
    Write-Info "Tool install started: $jbName"
}

Write-Info "Waiting for all $($jobs.Count) JumpBox installs..."
$jobs | Wait-Job | Receive-Job | Where-Object { $_ -match '(?i)error|fail|exception' } | ForEach-Object {
    Write-Warn "JumpBox warning: $_"
}
$jobs | Remove-Job
Write-OK "JumpBox tool installs done"

# -----------------------------------------------------------------------------
# Entra ID RBAC (optional, requires UsersCSV)
# -----------------------------------------------------------------------------
if ($userAssignments.Count -gt 0) {
    Write-Step "Entra ID RBAC assignments"

    # Install AADLoginForWindows extension on JumpBoxes
    for ($i = 1; $i -le $TeamCount; $i++) {
        $teamNum = '{0:D2}' -f $i
        $jbName  = "$Prefix-team-$teamNum"
        if (-not (Test-AzResourcePresence 'vm', 'extension', 'show', '--resource-group', $ResourceGroup,
                '--vm-name', $jbName, '--name', 'AADLoginForWindows')) {
            Invoke-AzCmd 'vm', 'extension', 'set',
                '--resource-group', $ResourceGroup, '--vm-name', $jbName,
                '--name', 'AADLoginForWindows',
                '--publisher', 'Microsoft.Azure.ActiveDirectory' | Out-Null
            Write-OK "AADLoginForWindows: $jbName"
        }
    }

    $rgId = az group show --name $ResourceGroup --query id -o tsv

    foreach ($row in $userAssignments) {
        $teamNum = '{0:D2}' -f [int]$row.teamNumber
        $jbName  = "$Prefix-team-$teamNum"
        $jbId    = az vm show --resource-group $ResourceGroup --name $jbName --query id -o tsv 2>$null

        if (-not $jbId) {
            Write-Warn "JumpBox not found for team $teamNum - skipping $($row.userPrincipalName)"
            continue
        }

        Invoke-AzCmd 'role', 'assignment', 'create',
            '--role', 'Virtual Machine User Login',
            '--assignee', $row.userPrincipalName,
            '--scope', $jbId.Trim() | Out-Null
        Invoke-AzCmd 'role', 'assignment', 'create',
            '--role', 'Reader',
            '--assignee', $row.userPrincipalName,
            '--scope', $rgId.Trim() | Out-Null
        Write-OK "RBAC: $($row.userPrincipalName) -> team $teamNum ($jbName)"
    }
}

# -----------------------------------------------------------------------------
# Auto-shutdown
# -----------------------------------------------------------------------------
if ($AutoShutdownTime) {
    Write-Step "Auto-shutdown @ ${AutoShutdownTime} UTC"
    foreach ($vmName in $allVmNames) {
        $vmId = az vm show --resource-group $ResourceGroup --name $vmName --query id -o tsv 2>$null
        if ($vmId) {
            $scheduleProperties = @{
                status           = 'Enabled'
                taskType         = 'ComputeVmShutdownTask'
                dailyRecurrence  = @{ time = $AutoShutdownTime }
                timeZoneId       = 'UTC'
                targetResourceId = $vmId.Trim()
            } | ConvertTo-Json -Compress

            $propsFile = Join-Path $env:TEMP "shutdown-$vmName.json"
            $scheduleProperties | Out-File -FilePath $propsFile -Encoding ascii -Force

            Invoke-AzCmd 'resource', 'create',
                '--resource-group', $ResourceGroup,
                '--resource-type', 'Microsoft.DevTestLab/schedules',
                '--name', "shutdown-computevm-$vmName",
                '--api-version', '2018-09-15',
                '--properties', "@$propsFile" | Out-Null

            Remove-Item -Path $propsFile -ErrorAction SilentlyContinue
            Write-Info "Auto-shutdown: $vmName"
        }
    }
    Write-OK "Auto-shutdown configured on all VMs"
}

# -----------------------------------------------------------------------------
# Optional: SQL Managed Instance (async, 3-6 hours)
# -----------------------------------------------------------------------------
if ($DeploySQLMI) {
    Write-Step "SQL Managed Instance (async - 3-6 hours)"
    Write-Warn "SQL MI costs ~`$540/month. Delete immediately after the workshop!"

    $miName   = "$Prefix-sqlmi"
    $miSubnet = az network vnet subnet show `
        --resource-group $ResourceGroup --vnet-name $vnetName --name snet-mi `
        --query id -o tsv 2>$null

    if (-not (Test-AzResourcePresence 'sql', 'mi', 'show', '--resource-group', $ResourceGroup, '--name', $miName)) {
        # NSG required by SQL MI
        $miNsg = "$Prefix-nsg-mi"
        if (-not (Test-AzResourcePresence 'network', 'nsg', 'show', '--resource-group', $ResourceGroup, '--name', $miNsg)) {
            Invoke-AzCmd 'network', 'nsg', 'create',
                '--resource-group', $ResourceGroup, '--name', $miNsg, '--location', $Location | Out-Null
            foreach ($port in @('9000','9003','1438','1440','1452')) {
                Invoke-AzCmd 'network', 'nsg', 'rule', 'create',
                    '--resource-group', $ResourceGroup, '--nsg-name', $miNsg,
                    "--name", "AllowMgmt$port", '--priority', (100 + [int]$port % 100).ToString(),
                    '--direction', 'Inbound', '--access', 'Allow', '--protocol', 'Tcp',
                    '--destination-port-ranges', $port,
                    '--source-address-prefixes', 'SqlManagement' | Out-Null
            }
            Invoke-AzCmd 'network', 'vnet', 'subnet', 'update',
                '--resource-group', $ResourceGroup, '--vnet-name', $vnetName,
                '--name', 'snet-mi', '--network-security-group', $miNsg | Out-Null
            Write-OK "SQL MI NSG configured"
        }

        Invoke-AzCmd 'sql', 'mi', 'create',
            '--resource-group', $ResourceGroup, '--name', $miName,
            '--location', $Location, '--subnet', $miSubnet.Trim(),
            '--admin-user', $AdminUsername, '--admin-password', $AdminPassword,
            '--tier', 'GeneralPurpose', '--family', 'Gen5', '--capacity', '4',
            '--storage', '32GB', '--license-type', 'BasePrice',
            '--no-wait' | Out-Null
        Write-OK "SQL MI started: $miName"
        Write-Info "Monitor: az sql mi show -g $ResourceGroup -n $miName --query provisioningState"
    } else {
        Write-OK "SQL MI exists: $miName"
    }
}

# -----------------------------------------------------------------------------
# Output: credentials CSV + connection guide
# -----------------------------------------------------------------------------
Write-Step "Generating output files"

$csvPath   = Join-Path $outDir 'team-credentials.csv'
$guidePath = Join-Path $outDir 'connection-guide.md'

$csvRows    = @('team,vmName,sqlLogin,sqlPassword,vmAdminUser,vmAdminPassword')
$guideLines = @(
    "# MicroHack SQL 2026 - Workshop Connection Guide",
    "",
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC",
    "Resource group: $ResourceGroup",
    "",
    "## Shared SQL Source VMs",
    "",
    "| VM | IP | Compat | Purpose |",
    "|----|----|--------|---------|",
    "| $Prefix-sql-2012 | 10.0.2.4,1433 | 110 (SQL 2012 sim) | Source A |",
    "| $Prefix-sql-2016 | 10.0.2.5,1433 | 130 (SQL 2016 sim) | Source B |",
    "",
    "## Per-Team JumpBoxes and SQL Credentials",
    "",
    "| Team | JumpBox VM | SQL Login | Databases (on each SQL VM) |",
    "|------|-----------|-----------|---------------------------|"
)

for ($i = 1; $i -le $TeamCount; $i++) {
    $teamNum    = '{0:D2}' -f $i
    $teamPrefix = "TEAM$teamNum"
    $jbName     = "$Prefix-team-$teamNum"
    $teamPass   = $teamPasswords[$teamNum]
    $teamLogin  = "team$teamNum"

    $csvRows    += "$teamPrefix,$jbName,$teamLogin,$teamPass,$AdminUsername,$AdminPassword"
    $guideLines += "| $teamPrefix | $jbName | $teamLogin | ${teamPrefix}_AdventureWorks2019, ${teamPrefix}_WideWorldImporters |"
}

$bastionUrl = "https://portal.azure.com/#@$TenantId/resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/bastionHosts/$bastionName/overview"

$guideLines += @(
    "",
    "## Access Instructions",
    "",
    "1. Open a Private/Incognito browser window",
    "2. Log in to the Azure Portal with your assigned credentials",
    "3. Navigate to: Resource Groups -> $ResourceGroup -> your JumpBox VM",
    "4. Click **Connect** -> **Bastion**",
    "5. Username: ``$AdminUsername`` | Password: see table above",
    "6. Find ``_SQLHACK_LAB_INFO.txt`` on the desktop for quick connection details",
    "",
    "Bastion portal link:",
    "``$bastionUrl``",
    "",
    "## Cost & Cleanup",
    "",
    "- All VMs auto-shutdown at ${AutoShutdownTime} UTC daily.",
    "- After the workshop: ``.\cleanup.ps1 -ResourceGroup $ResourceGroup``"
)

($csvRows    -join "`n") | Out-File $csvPath   -Encoding UTF8 -Force
($guideLines -join "`n") | Out-File $guidePath -Encoding UTF8 -Force

Write-OK "Credentials : $csvPath"
Write-OK "Guide       : $guidePath"

# -----------------------------------------------------------------------------
# Console summary
# -----------------------------------------------------------------------------
$sep = "=" * 60
Write-Host "`n$sep" -ForegroundColor Cyan
Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host "$sep" -ForegroundColor Cyan
Write-Host " Resource group  : $ResourceGroup ($Location)"
Write-Host " Teams           : $TeamCount"
Write-Host " SQL VMs         : $Prefix-sql-2012 (10.0.2.4), $Prefix-sql-2016 (10.0.2.5)"
Write-Host " JumpBox VMs     : $Prefix-team-01 .. $Prefix-team-$('{0:D2}' -f $TeamCount)"
Write-Host " Bastion         : $bastionName"
Write-Host " Storage account : $saName"
if ($DeploySQLMI) { Write-Host " SQL MI          : $Prefix-sqlmi (provisioning - check portal)" -ForegroundColor Yellow }
Write-Host ""
Write-Host " Credentials CSV : $csvPath"
Write-Host " Connection guide: $guidePath"
Write-Host " Deploy log      : $logFile"
Write-Host ""
Write-Host " Next steps:"
Write-Host "   Validate : .\validate.ps1 -ResourceGroup $ResourceGroup -TeamCount $TeamCount -Prefix $Prefix"
Write-Host "   Teardown : .\cleanup.ps1  -ResourceGroup $ResourceGroup"
Write-Host "$sep`n" -ForegroundColor Cyan

Stop-Transcript | Out-Null
