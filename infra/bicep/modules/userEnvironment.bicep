// userEnvironment.bicep — Everything inside a single student's resource group.
// Deployed at resourceGroup scope from main.bicep.

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Short, DNS-safe resource name prefix for this student, e.g. mhu01.')
param resourcePrefix string

@description('VM size for the source SQL VM.')
param vmSize string = 'Standard_D4s_v5'

@description('Local VM administrator username.')
param vmAdminUsername string

@description('Local VM administrator password (also used as SQL sa/admin password).')
@secure()
param vmAdminPassword string

@description('SQL/MI administrator login.')
param sqlAdminLogin string

@description('SQL/MI administrator password.')
@secure()
param sqlAdminPassword string

@description('Deploy the source VM.')
param deploySourceVm bool = true

@description('Deploy the Azure SQL Managed Instance.')
param deploySqlMi bool = true

@description('Raw URL of the CSE setup script.')
param setupScriptUri string = ''

@description('Daily auto-shutdown time HHmm UTC; empty disables it.')
param autoShutdownTime string = '1900'

@description('Extra resource tags for policy compliance, e.g. SecurityControl=Ignore.')
param resourceTags object = {}

module logAnalytics 'logAnalytics.bicep' = {
  name: 'logAnalytics'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    resourceTags: resourceTags
  }
}

module network 'network.bicep' = {
  name: 'network'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    deploySqlMi: deploySqlMi
  }
}

module bastion 'bastion.bicep' = if (deploySourceVm) {
  name: 'bastion'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    bastionSubnetId: network.outputs.bastionSubnetId
  }
}

module sourceVm 'sourceVm.bicep' = if (deploySourceVm) {
  name: 'sourceVm'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    sqlSubnetId: network.outputs.sqlSubnetId
    vmSize: vmSize
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    sqlAdminLogin: sqlAdminLogin
    setupScriptUri: setupScriptUri
    autoShutdownTime: autoShutdownTime
  }
}

module sqlServer 'sqlServer.bicep' = {
  name: 'sqlServer'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    resourceTags: resourceTags
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    resourceTags: resourceTags
  }
}

module sqlMi 'sqlMi.bicep' = if (deploySqlMi) {
  name: 'sqlMi'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    miSubnetId: network.outputs.miSubnetId
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    resourceTags: resourceTags
  }
}

#disable-next-line BCP318
output vmName string = deploySourceVm ? sourceVm.outputs.vmName : ''
#disable-next-line BCP318
output bastionName string = deploySourceVm ? bastion.outputs.bastionName : ''
output sqlServerFqdn string = sqlServer.outputs.sqlServerFqdn
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output logAnalyticsName string = logAnalytics.outputs.workspaceName
#disable-next-line BCP318
output sqlMiFqdn string = deploySqlMi ? sqlMi.outputs.managedInstanceFqdn : ''
