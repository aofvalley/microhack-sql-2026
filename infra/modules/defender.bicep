targetScope = 'subscription'

resource defenderSqlVm 'Microsoft.Security/pricings@2023-01-01' = {
  name: 'SqlServerVirtualMachines'
  properties: {
    pricingTier: 'Standard'
  }
}

resource defenderSqlMi 'Microsoft.Security/pricings@2023-01-01' = {
  name: 'SqlManagedInstances'
  properties: {
    pricingTier: 'Standard'
  }
}
