# Bicep IaC

This directory contains Bicep modules that reproduce the same environment as `scripts/deploy.ps1`,
with declarative infrastructure-as-code.

## Parameter parity matrix

| deploy.ps1 parameter | Bicep parameter | Default |
|---|---|---|
| `-Prefix` | `prefix` | `microhack-2026` |
| `-Location` | `location` | `eastus` |
| `-TeamCount` | `teamCount` | `2` |
| `-AdminUsername` | `adminUsername` | `sqladmin` |
| `-AdminPassword` | `adminPassword` | *(required, @secure)* |
| `-DeploySQLMI` | `deploySQLMI` | `false` |
| `-AutoShutdownTime` | `autoShutdownTime` | `1900` |
| `-BudgetAmount` | `budgetAmount` | `100` |
| `-BudgetContactEmail` | `budgetContactEmail` | *(required)* |

## Module structure

```
infra/
  main.bicep          Subscription-scoped orchestrator
  main.bicepparam     Parameter defaults
  modules/
    network.bicep     VNet, NSGs, subnets, Bastion
    sqlvm.bicep       SQL VM + CSE
    jumpbox.bicep     JumpBox VMs (loop per team) + CSE
    sqlmi.bicep       SQL Managed Instance (opt-in)
    monitoring.bicep  Log Analytics + Storage Account
    defender.bicep    Defender for SQL plans
    budget.bicep      Budget + Action Group alerts
```

## Deploy commands

Deploy via PowerShell wrapper:

```powershell
.\scripts\deploy.ps1 -UseBicep -TeamCount 2 -AdminPassword 'YourP@ss!' -BudgetContactEmail 'you@example.com'
```

Or directly with Az CLI:

```powershell
az deployment sub what-if --location eastus --template-file infra/main.bicep --parameters infra/main.bicepparam adminPassword='YourP@ss!'
az deployment sub create --location eastus --template-file infra/main.bicep --parameters infra/main.bicepparam adminPassword='YourP@ss!' budgetContactEmail='you@example.com'
```
