// sourceVm.bicep — Per-student migration SOURCE: Windows Server 2022 + SQL Server 2019 Developer.
// Sample databases + tooling are installed by a Custom Script Extension.

@description('Azure region.')
param location string

@description('Short resource name prefix for this student.')
param resourcePrefix string

@description('Resource id of the subnet for the VM.')
param sqlSubnetId string

@description('VM size.')
param vmSize string = 'Standard_D4s_v5'

@description('Local administrator username (also used as SQL admin login name reference).')
param adminUsername string

@description('Local administrator password (also passed as SQL sa / admin password to the CSE).')
@secure()
param adminPassword string

@description('SQL admin login name created inside SQL Server by the setup script.')
param sqlAdminLogin string

@description('Read-only URL (e.g. a SAS URL) of the setup-source-vm.ps1 Custom Script Extension script. Empty disables the CSE. deploy.ps1 stages the script in a storage account and passes a short-lived SAS URL so it works with a private repository.')
param setupScriptUri string = ''

@description('Daily auto-shutdown time HHmm in UTC. Empty disables auto-shutdown.')
param autoShutdownTime string = '1900'

var vmName = '${resourcePrefix}-srcvm'
var nicName = '${resourcePrefix}-srcvm-nic'
var pipName = '${resourcePrefix}-srcvm-pip'
var osDiskName = '${resourcePrefix}-srcvm-osdisk'
var scriptFileName = empty(setupScriptUri) ? '' : first(split(last(split(setupScriptUri, '/')), '?'))

// Regions where Microsoft.DevTestLab/schedules (auto-shutdown) is available.
var autoShutdownRegions = [
  'westcentralus', 'southcentralus', 'centralus', 'qatarcentral', 'australiacentral'
  'australiasoutheast', 'brazilsoutheast', 'canadacentral', 'centralindia', 'eastasia'
  'eastus', 'francecentral', 'japaneast', 'koreacentral', 'northeurope', 'southafricanorth'
  'switzerlandnorth', 'uaenorth', 'ukwest', 'westindia', 'australiacentral2', 'australiaeast'
  'brazilsouth', 'canadaeast', 'eastus2', 'francesouth', 'germanywestcentral', 'japanwest'
  'jioindiawest', 'koreasouth', 'northcentralus', 'norwayeast', 'southindia', 'southeastasia'
  'swedencentral', 'switzerlandwest', 'uksouth', 'westeurope', 'westus', 'westus2', 'westus3'
]
var autoShutdownEnabled = !empty(autoShutdownTime) && contains(autoShutdownRegions, location)

resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
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
          subnet: {
            id: sqlSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: take(replace('${resourcePrefix}srcvm', '-', ''), 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftSQLServer'
        offer: 'sql2019-ws2022'
        sku: 'sqldev-gen2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource setupExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (!empty(setupScriptUri)) {
  parent: vm
  name: 'setup-source-vm'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [ setupScriptUri ]
    }
    protectedSettings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File ${scriptFileName} -SaPassword "${adminPassword}" -SqlAdminLogin "${sqlAdminLogin}" -SqlAdminPassword "${adminPassword}"'
    }
  }
}

resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (autoShutdownEnabled) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: 'UTC'
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
  }
}

output vmName string = vm.name
output vmPublicIpId string = pip.id
