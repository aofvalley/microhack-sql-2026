// ============================================================================
// MicroHack SQL 2026 — LEAN infra for Challenge 01 (Assessment) + 02 (DMS).
// Scope: single SQL Server 2019 IaaS source VM + empty Azure SQL Database
// logical server (DMS target). No Bastion / jumpbox / MI / Defender / budget.
// Resource-group scoped. Deploy with: az deployment group create.
// ============================================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Azure region for the Azure SQL logical server (may differ if the primary region is restricted for SQL DB provisioning).')
param sqlLocation string = location

@description('Short prefix used in resource names.')
param prefix string = 'mh2026'

@description('Local administrator username for the SQL Server 2019 VM.')
param adminUsername string = 'sqladmin'

@description('Local administrator password for the SQL Server 2019 VM.')
@secure()
param adminPassword string

@description('Entra ID admin login (UPN) for the Azure SQL logical server. MCAPS policy enforces Entra-only auth.')
param aadAdminLogin string

@description('Entra ID admin object ID (sid) for the Azure SQL logical server.')
param aadAdminObjectId string

@description('Tenant ID for the Entra ID admin.')
param aadAdminTenantId string = subscription().tenantId

@description('Public IP (CIDR /32) allowed to RDP into the VM and reach the SQL logical server. Your current public IP.')
param allowedClientIp string

@description('VM size. D4s_v5 is enough for the lab.')
param vmSize string = 'Standard_D4s_v5'

@description('Daily auto-shutdown time (HHMM, UTC).')
param autoShutdownTime string = '1900'

// --- Names ---------------------------------------------------------------
var vnetName    = 'vnet-${prefix}'
var subnetName  = 'snet-sql'
var nsgName     = 'nsg-${prefix}'
var pipName     = 'pip-sqlvm-${prefix}'
var nicName     = 'nic-sqlvm-${prefix}'
var vmName      = 'sqlvm-${prefix}'
var sqlServerName = toLower('sqlsrv${prefix}${uniqueString(resourceGroup().id)}')

// --- Network -------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-FromClient'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedClientIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Allow-SQL-IntraVNet'
        properties: {
          priority: 1100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.0.0.0/16'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.0.0.0/16' ] }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: '${vnet.id}/subnets/${subnetName}' }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

// --- SQL Server 2019 source VM ------------------------------------------
resource sqlVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: { enableAutomaticUpdates: true }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftSQLServer'
        offer: 'sql2019-ws2022'
        sku: 'sqldev-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
  }
}

resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: autoShutdownTime }
    timeZoneId: 'UTC'
    targetResourceId: sqlVm.id
  }
}

// --- Azure SQL Database logical server (DMS target, empty) --------------
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: sqlLocation
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: aadAdminTenantId
      azureADOnlyAuthentication: true
    }
  }
}

resource fwAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource fwClient 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowClientIp'
  properties: {
    startIpAddress: allowedClientIp
    endIpAddress: allowedClientIp
  }
}

resource fwVm 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowSourceVmPublicIp'
  properties: {
    startIpAddress: pip.properties.ipAddress
    endIpAddress: pip.properties.ipAddress
  }
}

// --- Outputs -------------------------------------------------------------
output vmName string = vmName
output vmPublicIp string = pip.properties.ipAddress
output sqlServerName string = sqlServerName
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlAadAdmin string = aadAdminLogin
