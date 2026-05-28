@description('Azure region')
param location string

@description('Resource prefix')
param prefix string

@description('Admin username for SQL MI')
param adminUsername string

@description('Admin password for SQL MI')
@secure()
param adminPassword string

@description('Subnet resource ID for SQL MI')
param subnetId string

var miName = 'sqlmi-${prefix}-${uniqueString(resourceGroup().id)}'

resource sqlMi 'Microsoft.Sql/managedInstances@2023-08-01-preview' = {
  name: miName
  location: location
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    capacity: 4
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    subnetId: subnetId
    licenseType: 'LicenseIncluded'
    vCores: 4
    storageSizeInGB: 32
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    publicDataEndpointEnabled: false
    minimalTlsVersion: '1.2'
  }
}

output miName string = miName
output fqdn string = sqlMi.properties.fullyQualifiedDomainName
output miId string = sqlMi.id
