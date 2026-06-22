#Requires -RunAsAdministrator
<#
    Runs on SQL VMs via az vm run-command invoke after VM creation.
    Enables TCP/IP, opens Firewall 1433 for VNet, sets SQL Agent auto-start,
    creates C:\Lab\Backups folder and SqlBackups SMB share.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Custom Script Extension writes progress to console and log.')]
param()

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$msg)
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    $line | Tee-Object -FilePath 'C:\Lab\sqlvm-prereqs.log' -Append | Write-Host
}

New-Item -ItemType Directory -Path 'C:\Lab\Backups' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Lab\Data'    -Force | Out-Null
Write-Log "Lab directories created"

# Enable TCP/IP for default SQL Server instance via registry
$regSqlInstances = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
if (Test-Path $regSqlInstances) {
    Get-Item $regSqlInstances | Select-Object -ExpandProperty Property | ForEach-Object {
        $instanceId = (Get-ItemProperty $regSqlInstances).$_
        $tcpPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp"
        if (Test-Path $tcpPath) {
            Set-ItemProperty -Path $tcpPath -Name 'Enabled' -Value 1
            Write-Log "TCP/IP enabled for instance $_ ($instanceId)"
        }
    }
} else {
    Write-Log "WARNING: SQL instance registry path not found"
}

# Windows Firewall: allow 1433 from VNet (10.0.0.0/16) only
$fwRuleName = 'SQLServer-VNet-1433'
if (-not (Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $fwRuleName `
        -Direction Inbound -Protocol TCP -LocalPort 1433 `
        -RemoteAddress '10.0.0.0/16' -Action Allow | Out-Null
    Write-Log "Firewall rule created: $fwRuleName"
}

# SQL Server Agent: auto-start
$agentSvc = Get-Service -Name 'SQLSERVERAGENT' -ErrorAction SilentlyContinue
if ($agentSvc) {
    Set-Service -Name 'SQLSERVERAGENT' -StartupType Automatic
    Write-Log "SQL Server Agent startup set to Automatic"
}

# SMB share for DMS/LRS exercises
$shareName = 'SqlBackups'
if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $shareName -Path 'C:\Lab\Backups' -ChangeAccess 'Everyone' | Out-Null
    Write-Log "SMB share created: \\localhost\$shareName"
}

# Restart SQL Server to apply TCP/IP change
Write-Log "Restarting SQL Server..."
Restart-Service -Name 'MSSQLSERVER' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 20

if ($agentSvc) {
    Start-Service -Name 'SQLSERVERAGENT' -ErrorAction SilentlyContinue
    Write-Log "SQL Server Agent started"
}

Write-Log "SQL VM prerequisites complete"
