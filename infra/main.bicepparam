using 'main.bicep'

param prefix = 'microhack-2026'
param location = 'eastus'
param teamCount = 2
param adminUsername = 'sqladmin'
// adminPassword is required - pass via CLI: --parameters adminPassword='YourP@ss!'
param deploySQLMI = false
param autoShutdownTime = '1900'
param budgetAmount = 100
// budgetContactEmail is required - pass via CLI: --parameters budgetContactEmail='you@example.com'
