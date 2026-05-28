@description('Monthly budget amount in USD')
param budgetAmount int = 100

@description('Email address for budget alert notifications')
param contactEmail string

@description('Resource group name to scope the budget to')
param rgName string

var actionGroupName = 'ag-budget-${rgName}'

resource actionGroup 'microsoft.insights/actionGroups@2023-09-01-preview' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'BudgetAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'BudgetEmailReceiver'
        emailAddress: contactEmail
        useCommonAlertSchema: false
      }
    ]
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-${rgName}'
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2026-01-01'
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [rgName]
      }
    }
    notifications: {
      alert50: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        contactEmails: [contactEmail]
        thresholdType: 'Actual'
      }
      alert75: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 75
        contactEmails: [contactEmail]
        thresholdType: 'Actual'
      }
      alert90: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: [contactEmail]
        thresholdType: 'Actual'
      }
      alert100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [contactEmail]
        thresholdType: 'Actual'
      }
    }
  }
}
