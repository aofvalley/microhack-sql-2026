#Requires -Version 7.0
<#
    Post-deploy smoke test for the MicroHack SQL 2026 workshop environment.
    Checks: VMs running, SQL accessible, team DBs present, Bastion provisioned,
    auto-shutdown configured, storage account present.

    Usage: .\validate.ps1 -ResourceGroup rg-sqlhack-microhack-2026 -TeamCount 5 -Prefix sqlhack
#>

param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [int]    $TeamCount = 5,
    [string] $Prefix    = 'sqlhack'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$passCount  = 0
$failCount  = 0
$warnCount  = 0

function Write-Check {
    param([string]$label, [bool]$ok, [string]$detail = '')
    if ($ok) {
        Write-Host ("  [PASS] {0,-52} {1}" -f $label, $detail) -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host ("  [FAIL] {0,-52} {1}" -f $label, $detail) -ForegroundColor Red
        $script:failCount++
    }
}

function Write-Warn {
    param([string]$label, [string]$detail = '')
    Write-Host ("  [WARN] {0,-52} {1}" -f $label, $detail) -ForegroundColor Yellow
    $script:warnCount++
}

Write-Host "`n=== MicroHack SQL 2026 — Deployment Validation ===" -ForegroundColor Cyan
Write-Host "  Resource group : $ResourceGroup"
Write-Host "  Teams          : $TeamCount"
Write-Host "  Prefix         : $Prefix`n"

# Resource group
$rgOk = (az group show --name $ResourceGroup 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue) -ne $null
Write-Check "Resource group exists" $rgOk

# VNet
$vnetName = "$Prefix-vnet-shared"
$vnetOk   = (az network vnet show --resource-group $ResourceGroup --name $vnetName 2>$null) -ne $null
Write-Check "VNet: $vnetName" $vnetOk

# Azure Bastion
$bastionName = "$Prefix-bastion"
$bastionInfo = az network bastion show --resource-group $ResourceGroup --name $bastionName 2>$null |
               ConvertFrom-Json -ErrorAction SilentlyContinue
$bastionOk   = $bastionInfo -and $bastionInfo.provisioningState -eq 'Succeeded'
Write-Check "Bastion provisioned" $bastionOk $bastionInfo.provisioningState

# SQL VMs
foreach ($vmSuffix in @('sql-2012', 'sql-2016')) {
    $vmName = "$Prefix-$vmSuffix"
    $vmInfo = az vm show --resource-group $ResourceGroup --name $vmName --show-details 2>$null |
              ConvertFrom-Json -ErrorAction SilentlyContinue
    $vmOk   = $vmInfo -and $vmInfo.powerState -eq 'VM running'
    Write-Check "VM running: $vmName" $vmOk $vmInfo.powerState
}

# JumpBox VMs
for ($i = 1; $i -le $TeamCount; $i++) {
    $teamNum = '{0:D2}' -f $i
    $vmName  = "$Prefix-team-$teamNum"
    $vmInfo  = az vm show --resource-group $ResourceGroup --name $vmName --show-details 2>$null |
               ConvertFrom-Json -ErrorAction SilentlyContinue
    $vmOk    = $vmInfo -and $vmInfo.powerState -eq 'VM running'
    Write-Check "JumpBox running: $vmName" $vmOk $vmInfo.powerState
}

# Team databases via RunCommand
Write-Host "`n  Checking SQL databases via RunCommand (may take ~30s each)..." -ForegroundColor Cyan

foreach ($vmSuffix in @('sql-2012', 'sql-2016')) {
    $vmName  = "$Prefix-$vmSuffix"
    $query   = "SELECT name FROM sys.databases WHERE name LIKE 'TEAM%' ORDER BY name"
    $rcResult = az vm run-command invoke `
        --resource-group $ResourceGroup --name $vmName `
        --command-id RunPowerShellScript `
        --scripts "sqlcmd -S localhost -E -Q `"$query`" -h -1 -W -TrustServerCertificate" 2>$null |
        ConvertFrom-Json -ErrorAction SilentlyContinue

    if ($rcResult -and $rcResult.value) {
        $output  = $rcResult.value[0].message
        $dbCount = ([regex]::Matches($output, 'TEAM\d{2}_')).Count
        $expected = $TeamCount * 2   # AW2019 + WWI per team
        Write-Check "Team DBs on $vmName ($dbCount / $expected expected)" ($dbCount -ge $expected)
    } else {
        Write-Check "Team DBs on $vmName" $false "RunCommand failed or SQL unreachable"
    }
}

# Auto-shutdown
$shutdownMissing = @()
$allVms = @("$Prefix-sql-2012", "$Prefix-sql-2016") +
          (1..$TeamCount | ForEach-Object { "$Prefix-team-$('{0:D2}' -f $_)" })

foreach ($vm in $allVms) {
    $schedOk = (az resource show --resource-group $ResourceGroup `
                --resource-type 'Microsoft.DevTestLab/schedules' `
                --name "shutdown-computevm-$vm" 2>$null) -ne $null
    if (-not $schedOk) { $shutdownMissing += $vm }
}

if ($shutdownMissing.Count -eq 0) {
    Write-Check "Auto-shutdown on all VMs" $true
} else {
    Write-Warn "Auto-shutdown missing on $($shutdownMissing.Count) VM(s)" ($shutdownMissing -join ', ')
}

# Storage account
$saList = az storage account list --resource-group $ResourceGroup `
    --query "[?starts_with(name,'$($Prefix -replace '-','')sa')]" 2>$null |
    ConvertFrom-Json -ErrorAction SilentlyContinue
Write-Check "Storage account present" ($saList.Count -gt 0) ($saList[0].name)

# Summary
Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
Write-Host "  PASS : $passCount" -ForegroundColor Green
if ($failCount -gt 0) { Write-Host "  FAIL : $failCount" -ForegroundColor Red }
if ($warnCount -gt 0) { Write-Host "  WARN : $warnCount" -ForegroundColor Yellow }

if ($failCount -eq 0) {
    Write-Host "`nAll checks passed. Environment ready for the workshop.`n" -ForegroundColor Green
} else {
    Write-Host "`n$failCount check(s) failed. Review errors above.`n" -ForegroundColor Red
    exit 1
}
