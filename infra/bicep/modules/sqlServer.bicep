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

@description('Microsoft Entra ID administrator login (UPN or display name). Empty leaves SQL authentication only.')
param entraAdminLogin string = ''

@description('Microsoft Entra ID administrator object id (principal/SID). Required when entraAdminLogin is set.')
param entraAdminObjectId string = ''

var enableEntraAdmin = !empty(entraAdminLogin) && !empty(entraAdminObjectId)

var sqlServerName = toLower('${resourcePrefix}-sqlsrv-${uniqueString(resourceGroup().id)}')

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: resourceTags
  properties: {
    // SQL authentication (username/password) stays enabled; Microsoft Entra ID
    // authentication is added on top when an Entra admin is supplied, so the
    // server accepts both authentication methods (azureADOnlyAuthentication=false).
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    administrators: enableEntraAdmin ? {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: entraAdminLogin
      sid: entraAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: false
    } : null
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
