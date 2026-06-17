// sqlMi.bicep — Per-student Azure SQL Managed Instance (Challenge 3 MI Link target).
// Public data endpoint enabled to avoid private connectivity complexity for the lab.

@description('Azure region.')
param location string

@description('Short resource name prefix for this student.')
param resourcePrefix string

@description('Resource id of the delegated MI subnet.')
param miSubnetId string

@description('MI administrator login.')
param sqlAdminLogin string

@description('MI administrator password.')
@secure()
param sqlAdminPassword string

@description('MI SKU name, e.g. GP_Gen5.')
param skuName string = 'GP_Gen5'

@description('MI tier.')
param skuTier string = 'GeneralPurpose'

@description('vCores.')
param vCores int = 4

@description('Reserved storage in GB.')
param storageSizeInGB int = 32

@description('Extra resource tags, e.g. SecurityControl=Ignore, to satisfy MCAPS governance policies when testing.')
param resourceTags object = {}

var miName = toLower('${resourcePrefix}-sqlmi-${uniqueString(resourceGroup().id)}')

resource managedInstance 'Microsoft.Sql/managedInstances@2025-08-01-preview' = {
  name: miName
  location: location
  tags: resourceTags
  sku: {
    name: skuName
    tier: skuTier
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    subnetId: miSubnetId
    licenseType: 'LicenseIncluded'
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    publicDataEndpointEnabled: true
    proxyOverride: 'Proxy'
    minimalTlsVersion: '1.2'
    databaseFormat: 'SQLServer2025'
    zoneRedundant: false
    databaseFormat: 'SQLServer2025'
  }
}

output managedInstanceName string = managedInstance.name
output managedInstanceFqdn string = managedInstance.properties.fullyQualifiedDomainName
