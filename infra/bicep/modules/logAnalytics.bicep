// logAnalytics.bicep — Per-student Log Analytics workspace.
// Used to collect diagnostics/telemetry for the student's lab resources
// (e.g. source VM, Azure SQL, SQL Managed Instance + MI Link monitoring).

@description('Azure region.')
param location string

@description('Short resource name prefix for this student, e.g. mhu01.')
param resourcePrefix string

@description('Daily data retention in days for the workspace.')
@minValue(7)
@maxValue(730)
param retentionInDays int = 30

@description('Extra resource tags, e.g. SecurityControl=Ignore, to satisfy MCAPS governance policies when testing.')
param resourceTags object = {}

var workspaceName = toLower('${resourcePrefix}-law')

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
