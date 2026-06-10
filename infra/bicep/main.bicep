// main.bicep — Subscription-scoped entry point.
// Creates one resource group per student and deploys their full lab environment.

targetScope = 'subscription'

@description('Number of students to provision.')
@minValue(1)
@maxValue(50)
param userCount int = 30

@description('First student index (useful to add students incrementally).')
@minValue(1)
param startUserIndex int = 1

@description('Azure region for all resources.')
param location string = 'westeurope'

@description('Short, lowercase prefix used for resource group and resource names.')
@maxLength(8)
param namePrefix string = 'mh'

@description('Local VM administrator username.')
param vmAdminUsername string = 'mhadmin'

@description('Local VM administrator password (also used as the SQL sa/admin password).')
@secure()
param vmAdminPassword string

@description('Azure SQL / Managed Instance administrator login.')
param sqlAdminLogin string = 'sqladmin'

@description('Azure SQL / Managed Instance administrator password.')
@secure()
param sqlAdminPassword string

@description('Deploy the per-student source SQL VM.')
param deploySourceVm bool = true

@description('Deploy the per-student Azure SQL Managed Instance (slow, ~3-6h, and costly).')
param deploySqlMi bool = true

@description('VM size for the source SQL VM.')
param vmSize string = 'Standard_D4s_v5'

@description('Daily auto-shutdown time HHmm UTC for the source VM; empty disables it.')
param autoShutdownTime string = '1900'

@description('Raw URL of the CSE setup-source-vm.ps1 script.')
param setupScriptUri string = ''

@description('Tags applied to every resource group.')
param tags object = {
  workload: 'microhack-sql-2026'
  managedBy: 'bicep'
}

@description('Extra tags applied to policy-sensitive resources (SQL Server, SQL MI). Set SecurityControl=Ignore to satisfy MCAPS governance deny policies when testing in a Microsoft-internal tenant.')
param resourceTags object = {}

var userIndexes = range(startUserIndex, userCount)

resource userRgs 'Microsoft.Resources/resourceGroups@2023-07-01' = [for i in userIndexes: {
  name: 'rg-${namePrefix}-user${padLeft(string(i), 2, '0')}'
  location: location
  tags: tags
}]

module userEnv 'modules/userEnvironment.bicep' = [for (i, idx) in userIndexes: {
  name: 'env-user${padLeft(string(i), 2, '0')}'
  scope: userRgs[idx]
  params: {
    location: location
    resourcePrefix: '${namePrefix}u${padLeft(string(i), 2, '0')}'
    vmSize: vmSize
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    deploySourceVm: deploySourceVm
    deploySqlMi: deploySqlMi
    setupScriptUri: setupScriptUri
    autoShutdownTime: autoShutdownTime
    resourceTags: resourceTags
  }
}]

output users array = [for (i, idx) in userIndexes: {
  index: i
  resourceGroup: userRgs[idx].name
  vmName: userEnv[idx].outputs.vmName
  bastionName: userEnv[idx].outputs.bastionName
  sqlServerFqdn: userEnv[idx].outputs.sqlServerFqdn
  sqlMiFqdn: userEnv[idx].outputs.sqlMiFqdn
  keyVaultName: userEnv[idx].outputs.keyVaultName
  logAnalyticsName: userEnv[idx].outputs.logAnalyticsName
}]
