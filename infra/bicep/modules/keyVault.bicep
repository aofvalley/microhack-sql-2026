// keyVault.bicep — Per-student Azure Key Vault that stores all lab credentials.
// RBAC-authorization mode: students get data-plane read via the "Key Vault Secrets User"
// role (granted by scripts/create-users.ps1). The facilitator deploying this template is
// Owner/Contributor, so the ARM secrets/write management action succeeds without granting
// the deployer any data-plane role. Purge protection is left unset (defaults to OFF) so cleanup
// can fully purge it — note Key Vault rejects setting enablePurgeProtection to false explicitly,
// so the property must be omitted rather than set to false.

@description('Azure region.')
param location string

@description('Short resource name prefix for this student, e.g. mhu01.')
param resourcePrefix string

@description('Local VM administrator username.')
param vmAdminUsername string

@description('Local VM administrator password (also used as the SQL sa/admin password on the VM).')
@secure()
param vmAdminPassword string

@description('Azure SQL / Managed Instance administrator login.')
param sqlAdminLogin string

@description('Azure SQL / Managed Instance administrator password.')
@secure()
param sqlAdminPassword string

@description('Extra resource tags for policy compliance, e.g. SecurityControl=Ignore.')
param resourceTags object = {}

// Vault names are globally unique and capped at 24 chars; build one that starts with a letter.
var keyVaultName = toLower('${resourcePrefix}kv${take(uniqueString(resourceGroup().id), 8)}')

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource secretVmUser 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'vm-admin-username'
  properties: {
    value: vmAdminUsername
  }
}

resource secretVmPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'vm-admin-password'
  properties: {
    value: vmAdminPassword
  }
}

resource secretSqlLogin 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-login'
  properties: {
    value: sqlAdminLogin
  }
}

resource secretSqlPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
