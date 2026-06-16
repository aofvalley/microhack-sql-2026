// network.bicep — Per-student VNet, subnets and NSGs.
// Public networking is used across the lab for simplicity, but the VM has no
// inbound NSG rules except Bastion; SQL/MI use their own public endpoints + firewall.

@description('Azure region.')
param location string

@description('Short resource name prefix for this student, e.g. mhu01.')
param resourcePrefix string

@description('VNet address space, e.g. 10.0.0.0/16.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet for the source SQL VM.')
param sqlSubnetPrefix string = '10.0.1.0/24'

@description('AzureBastionSubnet prefix (/26 minimum).')
param bastionSubnetPrefix string = '10.0.2.0/26'

@description('Subnet delegated to SQL Managed Instance.')
param miSubnetPrefix string = '10.0.4.0/24'

@description('Deploy the SQL MI subnet, NSG and route table.')
param deploySqlMi bool = true

var vnetName = '${resourcePrefix}-vnet'
var sqlNsgName = '${resourcePrefix}-sql-nsg'
var miNsgName = '${resourcePrefix}-mi-nsg'
var miRouteTableName = '${resourcePrefix}-mi-rt'

resource sqlNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: sqlNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-Internet'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SQL-1433'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SQL-5022'
        properties: {
          priority: 1020
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// NSG required by SQL Managed Instance. Rules per Microsoft docs for MI subnets.
resource miNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = if (deploySqlMi) {
  name: miNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow_management_inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [ '9000', '9003', '1438', '1440', '1452' ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_misubnet_inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: miSubnetPrefix
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_health_probe_inbound'
        properties: {
          priority: 300
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_tds_inbound'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_redirect_inbound'
        properties: {
          priority: 1100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '11000-11999'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_geodr_inbound'
        properties: {
          priority: 1200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'deny_all_inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SQL-5022'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'allow_management_outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [ '443', '12000' ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
      {
        name: 'allow_misubnet_outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: miSubnetPrefix
        }
      }
    ]
  }
}

// Route table required for SQL MI to keep management traffic symmetric.
resource miRouteTable 'Microsoft.Network/routeTables@2023-09-01' = if (deploySqlMi) {
  name: miRouteTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: concat([
        {
          name: 'snet-sql'
          properties: {
            addressPrefix: sqlSubnetPrefix
            networkSecurityGroup: {
              id: sqlNsg.id
            }
          }
        }
        {
          name: 'AzureBastionSubnet'
          properties: {
            addressPrefix: bastionSubnetPrefix
          }
        }
      ], deploySqlMi ? [
        {
          name: 'snet-mi'
          properties: {
            addressPrefix: miSubnetPrefix
            networkSecurityGroup: {
              id: miNsg.id
            }
            routeTable: {
              id: miRouteTable.id
            }
            delegations: [
              {
                name: 'miDelegation'
                properties: {
                  serviceName: 'Microsoft.Sql/managedInstances'
                }
              }
            ]
          }
        }
      ] : [])
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output sqlSubnetId string = vnet.properties.subnets[0].id
output bastionSubnetId string = vnet.properties.subnets[1].id
output miSubnetId string = deploySqlMi ? vnet.properties.subnets[2].id : ''
