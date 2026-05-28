@description('Azure region')
param location string

@description('Resource prefix')
param prefix string

var vnetName = 'vnet-${prefix}'
var bastionPipName = 'pip-bastion-${prefix}'
var bastionName = 'bastion-${prefix}'

resource sqlNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-sql-${prefix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-rdp-from-bastion'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.0.3.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'allow-sql-from-jumpbox'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.0.2.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
    ]
  }
}

resource jumpboxNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-jumpbox-${prefix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-rdp-from-bastion'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.0.3.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
    ]
  }
}

resource miNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-mi-${prefix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-mi-management'
        properties: {
          priority: 100
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'SqlManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'sqlSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: { id: sqlNsg.id }
        }
      }
      {
        name: 'jumpboxSubnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { id: jumpboxNsg.id }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.3.0/27'
        }
      }
      {
        name: 'miSubnet'
        properties: {
          addressPrefix: '10.0.4.0/24'
          networkSecurityGroup: { id: miNsg.id }
          delegations: [
            {
              name: 'mi-delegation'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: bastionPipName
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: { id: '${vnet.id}/subnets/AzureBastionSubnet' }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output sqlSubnetId string = '${vnet.id}/subnets/sqlSubnet'
output jumpboxSubnetId string = '${vnet.id}/subnets/jumpboxSubnet'
output miSubnetId string = '${vnet.id}/subnets/miSubnet'
output bastionName string = bastionName
