# MicroHack SQL 2026 — Infrastructure Scripts

Scripts to deploy and tear down the full multi-team workshop environment.

## Prerequisites

- PowerShell 7.0+
- Azure CLI 2.60+ (`az --version`)
- Az PowerShell module 11+ (`Install-Module Az -Scope CurrentUser`)
- Logged in to Azure: `az login --tenant <your-tenant-id>`
- Contributor role on target subscription

## Quick start

```powershell
# 1. Copy and fill the parameter template
cp parameters.example.json parameters.json
# Edit parameters.json with your SubscriptionId, TenantId, TeamCount, etc.

# 2. Dry run (no resources created)
.\deploy.ps1 -SubscriptionId <sub> -TenantId <tid> -DryRun

# 3. Deploy (default: 1 team, no SQL MI — change -TeamCount for a workshop)
.\deploy.ps1 -SubscriptionId <sub> -TenantId <tid>

# 4. Validate after deploy
.\validate.ps1 -ResourceGroup rg-sqlhack-microhack-2026 -TeamCount 1

# 5. Tear down after workshop
.\cleanup.ps1 -ResourceGroup rg-sqlhack-microhack-2026
```

## deploy.ps1 parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SubscriptionId` | required | Azure subscription ID |
| `TenantId` | required | Entra ID tenant ID |
| `TeamCount` | 1 | Number of teams (1–50). Each team gets its own JumpBox + SQL login + per-team databases. Use 1 for a single user lab. |
| `Location` | westeurope | Azure region |
| `ResourceGroup` | rg-sqlhack-microhack-2026 | Resource group name |
| `Prefix` | sqlhack | Prefix for all resource names |
| `AdminUsername` | DemoUser | Local VM admin and SQL admin username |
| `AdminPassword` | (auto-generated) | Leave blank to auto-generate |
| `DeploySQLMI` | false | Deploy SQL Managed Instance (3-6h, ~$540/mo) |
| `UsersCSV` | (empty) | Path to CSV for Entra ID RBAC assignment |
| `AutoShutdownTime` | 1900 | Daily auto-shutdown HHmm UTC; empty to disable |
| `DryRun` | false | Print plan without creating resources |

## Architecture deployed

```
SQLHACK-SHARED-VNET (10.0.0.0/16)
├── snet-mi         (10.0.1.0/24)  → SQL Managed Instance (optional)
├── snet-mgmt       (10.0.2.0/24)  → sqlhack-sql-2012 (10.0.2.4) + sqlhack-sql-2016 (10.0.2.5)
├── snet-jumpboxes  (10.0.3.0/24)  → sqlhack-team-01 .. sqlhack-team-NN
└── AzureBastionSubnet (10.0.4.0/26) → Azure Bastion (Basic SKU)
```

**SQL VMs** (shared across all teams):

| VM | IP | Simulates | Per-team databases |
|----|----|-----------|-------------------|
| `sqlhack-sql-2012` | 10.0.2.4 | SQL 2012 (compat 110) | `TEAM01_AdventureWorks2019`, `TEAM01_WideWorldImporters` |
| `sqlhack-sql-2016` | 10.0.2.5 | SQL 2016 (compat 130) | same, different compat level |

**JumpBox VMs** (one per team): Windows Server 2022 with SSMS 20, Azure CLI, VS Code + MSSQL extension.

**SQL logins**: `team01`, `team02`, … with `db_owner` on their 4 databases only.

## Entra ID user assignment (optional)

```powershell
cp users.csv.example my-users.csv
# Edit my-users.csv with real userPrincipalNames and teamNumbers
.\deploy.ps1 -SubscriptionId <sub> -TenantId <tid> -UsersCSV .\my-users.csv
```

Each user gets `Virtual Machine User Login` on their JumpBox and `Reader` on the resource group.

## Output files (`out/`)

| File | Contents |
|------|----------|
| `team-credentials.csv` | SQL login, SQL password, VM admin credentials per team |
| `connection-guide.md` | Instructions with Bastion URL for facilitator to share |
| `deploy-<timestamp>.log` | Full transcript of the deployment run |

## Estimated costs

| Resource | Est. cost/hr |
|----------|-------------|
| 2× SQL VM Standard_D4s_v5 | ~$0.38 each |
| N× JumpBox Standard_D2s_v5 | ~$0.10 each |
| Azure Bastion Basic | ~$0.19 |
| SQL MI GP 4 vCore (optional) | ~$0.75 — **delete after lab** |

All VMs auto-shutdown at 19:00 UTC. Run `.\cleanup.ps1` after the workshop to avoid ongoing charges.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `az sql vm create` fails | `az extension add --name sql-vm --upgrade` |
| DB restore times out | Check `C:\Lab\setup-dbs.log` on the SQL VM via RDP or RunCommand |
| JumpBox tools missing | Check `C:\Lab\jumpbox-tools.log` on the JumpBox VM |
| Sample .bak download fails | Check outbound internet access; see `C:\Lab\download-dbs.log` |
| SQL MI stuck provisioning | Verify subnet delegation and NSG — see [MS docs](https://learn.microsoft.com/azure/azure-sql/managed-instance/connectivity-architecture-overview) |
