// add-mi.bicep — Adds an Azure SQL Managed Instance to an EXISTING student environment.
//
// Use this when a student resource group was originally deployed with deploySqlMi=false
// (for example because of regional MI capacity during the initial rollout) and the MI now
// needs to be added without redeploying or disturbing the VMs, Azure SQL server or Key Vault.
//
// It adds only: the delegated snet-mi subnet (into the existing VNet), the MI NSG, the MI
// route table, and the Managed Instance itself. NSG rules mirror modules/network.bicep,
// including inbound TCP 3342 for the public endpoint.

targetScope = 'resourceGroup'

@description('Azure region (must match the existing VNet region).')
param location string

@description('Short, DNS-safe resource name prefix for this student, e.g. mhu17.')
param resourcePrefix string

@description('Subnet delegated to SQL Managed Instance (must be free inside the existing VNet address space).')
param miSubnetPrefix string = '10.0.4.0/24'

@description('MI administrator login (use the value already stored in the student Key Vault).')
param sqlAdminLogin string

@description('MI administrator password (use the value already stored in the student Key Vault).')
@secure()
param sqlAdminPassword string

@description('Extra resource tags, e.g. SecurityControl=Ignore, to satisfy MCAPS governance policies.')
param resourceTags object = {}

var vnetName = '${resourcePrefix}-vnet'
var miNsgName = '${resourcePrefix}-mi-nsg'
var miRouteTableName = '${resourcePrefix}-mi-rt'

resource miNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
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
        name: 'Allow-5022-Any-Inbound'
        properties: {
          priority: 400
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: '*'
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
        name: 'allow_public_endpoint_inbound'
        properties: {
          priority: 1300
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3342'
          sourceAddressPrefix: 'Internet'
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

resource miRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: miRouteTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
}

// Added as a standalone subnet resource so the existing VNet/subnets are not redefined.
resource miSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
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

module sqlMi 'modules/sqlMi.bicep' = {
  name: 'sqlMi'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    miSubnetId: miSubnet.id
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    resourceTags: resourceTags
  }
}

output managedInstanceName string = sqlMi.outputs.managedInstanceName
output managedInstanceFqdn string = sqlMi.outputs.managedInstanceFqdn
