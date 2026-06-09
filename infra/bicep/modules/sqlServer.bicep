// sqlServer.bicep — Per-student Azure SQL logical server (Challenge 2 DMS target).
// No databases are pre-created; students create their own target DB during the lab.

@description('Azure region.')
param location string

@description('Short resource name prefix for this student (used to build a globally-unique server name).')
param resourcePrefix string

@description('SQL administrator login.')
param sqlAdminLogin string

@description('MI administrator password.')
@secure()
param sqlAdminPassword string

@description('Extra resource tags, e.g. SecurityControl=Ignore, to satisfy MCAPS governance policies when testing.')
param resourceTags object = {}

var sqlServerName = toLower('${resourcePrefix}-sqlsrv-${uniqueString(resourceGroup().id)}')

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: resourceTags
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Allow Azure services (DMS, etc.).
resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Public communication is used for the lab to avoid private-endpoint complexity.
resource allowAll 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllForLab'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
