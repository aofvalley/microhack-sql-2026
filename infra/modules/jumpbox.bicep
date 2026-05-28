@description('Azure region')
param location string

@description('Resource prefix')
param prefix string

@description('Team number (1-50)')
param teamNumber int

@description('Local admin username')
param adminUsername string

@description('Local admin password')
@secure()
param adminPassword string

@description('Subnet resource ID for the JumpBox NIC')
param subnetId string

@description('Auto-shutdown time HHMM UTC')
param autoShutdownTime string = '1900'

var teamSuffix = padLeft(string(teamNumber), 2, '0')
var vmName = 'jb-team-${teamSuffix}-${prefix}'
var nicName = 'nic-jb-${teamSuffix}-${prefix}'

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

resource jumpbox 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_v5' }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: { enableAutomaticUpdates: true }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

resource cse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: jumpbox
  name: 'jumpbox-tools'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/aofvalley/microhack-sql-2026/main/scripts/install-jumpbox-tools.ps1'
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File install-jumpbox-tools.ps1'
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
    targetResourceId: jumpbox.id
  }
}

output vmName string = vmName
output vmId string = jumpbox.id
