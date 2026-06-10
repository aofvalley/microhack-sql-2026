// bastion.bicep — Per-student Azure Bastion (Basic SKU) for browser-based RDP to the source VM.

@description('Azure region.')
param location string

@description('Short resource name prefix for this student.')
param resourcePrefix string

@description('Resource id of the AzureBastionSubnet.')
param bastionSubnetId string

var bastionName = '${resourcePrefix}-bastion'
var bastionPipName = '${resourcePrefix}-bastion-pip'

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: bastionPipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

output bastionName string = bastion.name
