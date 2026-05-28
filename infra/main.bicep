targetScope = 'subscription'

@description('Prefix for all resource names')
param prefix string = 'microhack-2026'

@description('Azure region for all resources')
param location string = 'eastus'

@description('Number of teams (1-50)')
@minValue(1)
@maxValue(50)
param teamCount int = 2

@description('Local admin username for VMs')
param adminUsername string = 'sqladmin'

@description('Local admin password for VMs')
@secure()
param adminPassword string

@description('Deploy SQL Managed Instance (adds 4-6h provisioning time)')
param deploySQLMI bool = false

@description('Auto-shutdown time in HHMM format UTC')
param autoShutdownTime string = '1900'

@description('Monthly budget amount in USD for alerts')
param budgetAmount int = 100

@description('Email address for budget alert notifications')
param budgetContactEmail string

var rgName = 'rg-sqlhack-${prefix}'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
}

module network 'modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    location: location
    prefix: prefix
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    prefix: prefix
  }
}

module sqlvm 'modules/sqlvm.bicep' = {
  name: 'sqlvm'
  scope: rg
  params: {
    location: location
    prefix: prefix
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.sqlSubnetId
    autoShutdownTime: autoShutdownTime
  }
}

module jumpboxes 'modules/jumpbox.bicep' = [for i in range(1, teamCount + 1): {
  name: 'jumpbox-team-${padLeft(string(i), 2, '0')}'
  scope: rg
  params: {
    location: location
    prefix: prefix
    teamNumber: i
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.jumpboxSubnetId
    autoShutdownTime: autoShutdownTime
  }
}]

module defender 'modules/defender.bicep' = {
  name: 'defender'
  scope: subscription()
  params: {}
}

module budget 'modules/budget.bicep' = {
  name: 'budget'
  scope: rg
  params: {
    budgetAmount: budgetAmount
    contactEmail: budgetContactEmail
    rgName: rgName
  }
}

module sqlmi 'modules/sqlmi.bicep' = if (deploySQLMI) {
  name: 'sqlmi'
  scope: rg
  params: {
    location: location
    prefix: prefix
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.miSubnetId
  }
}
