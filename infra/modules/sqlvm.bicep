@description('Azure region')
param location string

@description('Resource prefix')
param prefix string

@description('Local admin username')
param adminUsername string

@description('Local admin password')
@secure()
param adminPassword string

@description('Subnet resource ID for the SQL VM NIC')
param subnetId string

@description('Auto-shutdown time HHMM UTC')
param autoShutdownTime string = '1900'

var vmName = 'sqlhack-sqlvm-${prefix}'
var nicName = 'nic-sqlvm-${prefix}'

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource sqlVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_D4s_v5' }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: { enableAutomaticUpdates: true }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftSQLServer'
        offer: 'sql2022-ws2022'
        sku: 'sqldev-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

resource cse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: sqlVm
  name: 'sqlvm-prereqs'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/aofvalley/microhack-sql-2026/main/scripts/install-sqlvm-prereqs.ps1'
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File install-sqlvm-prereqs.ps1'
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

output vmName string = vmName
output vmId string = sqlVm.id
