# Architecture

## High-level diagram

```
Internet
    |
    |  (no public IPs on VMs)
    v
Azure Bastion (Basic SKU)
    |
    +-- JumpBox-Team-01  (Standard_D2s_v5, WS2022)
    +-- JumpBox-Team-02  ...
    |
    +-- SQL-VM-Team-01   (Standard_D4s_v5, SQL 2022 on WS2022)
    +-- SQL-VM-Team-02   ...
    |
    +-- SQL MI           (GP_Gen5_4, opt-in via -DeploySQLMI)

All VMs share a single VNet (10.0.0.0/16) with four subnets:
  - sqlSubnet       10.0.1.0/24
  - jumpboxSubnet   10.0.2.0/24
  - bastionSubnet   10.0.3.0/24 (AzureBastionSubnet, /27 minimum)
  - miSubnet        10.0.4.0/24 (delegated to managedInstances/databases)
```

## Component table

| Component | SKU / Image | Per team | Notes |
|---|---|---|---|
| SQL VM | Standard_D4s_v5, SQL 2022 Developer on WS2022 | 1 | CSE installs AdventureWorks2019 + WWI |
| JumpBox | Standard_D2s_v5, WS2022 | 1 | CSE installs SSMS 20, Az CLI, VS Code MSSQL |
| Azure Bastion | Basic SKU | Shared | Sole ingress; no public IPs on VMs |
| SQL MI | GP_Gen5_4vCores | Shared (opt-in) | Deployed when `-DeploySQLMI` is true |
| Storage Account | LRS, Standard | Shared | `backups` container for LRS/DMS backup files |
| Log Analytics | PerGB2018, 30-day retention | Shared | Target for Azure Monitor, Database Watcher |
| Defender for SQL | Standard tier | Shared (opt-in) | ~$15/server/month |
| Auto-shutdown | DevTest Labs schedule | Per VM | Default 19:00 UTC |

## Network security

| NSG | Rule | Direction | Action |
|---|---|---|---|
| sql-nsg | RDP from bastionSubnet | Inbound | Allow |
| sql-nsg | SQL from jumpboxSubnet (1433) | Inbound | Allow |
| sql-nsg | All other inbound | Inbound | Deny |
| jumpbox-nsg | RDP from bastionSubnet | Inbound | Allow |
| jumpbox-nsg | All other inbound | Inbound | Deny |
| mi-nsg | MI-required ports | Inbound/Outbound | Allow (per MS docs) |

## Per-team isolation

Each team gets their own SQL VM and JumpBox. SQL logins are scoped to `TEAM0X_*` databases.
Teams cannot access each other's VMs (NSG rules are VM-level; no cross-team SQL login is provisioned).

## Deployment paths

| Path | Command | Notes |
|---|---|---|
| PowerShell (standard) | `deploy.ps1 -TeamCount N [options]` | Idempotent; 11 parameters |
| Bicep (opt-in) | `deploy.ps1 -UseBicep -TeamCount N [options]` | Delegates to `az deployment sub create` |
