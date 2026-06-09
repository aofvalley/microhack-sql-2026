# Runbook — Challenge 01 (Assessment) + 02 (DMS → Azure SQL Database)

> Personal lean runbook for the **single SQL Server 2019 IaaS** setup deployed by
> `infra/microhack-min/main.bicep`. It adapts the official multi-instance challenges
> (`challenges/challenge-01.md`, `challenges/challenge-02.md`) to **one source VM + one
> Azure SQL Database target**, end to end, no over-engineering.
>
> Source DB used for both challenges: **`TEAM01_AdventureWorks2019`** restored at
> **compatibility level 110** on purpose, so DMA/Azure Migrate surface real legacy
> assessment findings (`DbCompatLevelLowerThan100`-style rules, deprecated features).

---

## 0. What is deployed (current environment)

| Item | Value |
| --- | --- |
| Resource group | `rg-microhack-sql-2026` |
| Source VM | `sqlvm-mh2026` (SQL Server 2019 Developer, West Europe) |
| VM public IP | `40.118.6.179` |
| VM admin user | `sqladmin` (password in your session creds file — never commit) |
| Source DB | `TEAM01_AdventureWorks2019` (ONLINE, compat **110**) |
| Backups on VM | `C:\Lab\Backups\*.bak`, data files in `C:\Lab\Data` |
| Target logical server | `sqlsrvmh2026tin4vcwzqrg3k.database.windows.net` (France Central) |
| Target auth | **Entra-only** (MCAPS policy `AzureSQL_WithoutAzureADOnlyAuthentication_Deny`) |
| Target Entra admin | `admin@MngEnvMCAP872561.onmicrosoft.com` |
| Firewall (target) | your client IP + `AllowAzureServices` (for DMS) + source VM IP |
| NSG | RDP 3389 from your client IP; 1433 intra-VNet only |

> ⚠️ **Entra-only target is the key gotcha for C02.** You cannot create a SQL login on
> the target. DMS must connect to the target with **Microsoft Entra** auth, and the
> migration principal must be an Entra user/SPN granted the four `##MS_*##` server roles
> (see §2.4).

### Refresh the live values any time

```powershell
az sql server list -g rg-microhack-sql-2026 --query "[].{name:name,fqdn:fullyQualifiedDomainName,state:state}" -o table
az vm list -d -g rg-microhack-sql-2026 --query "[].{name:name,power:powerState,ip:publicIps}" -o table
```

If your public IP changed, refresh the NSG + SQL firewall rules:

```powershell
$ip = (Invoke-RestMethod "https://api.ipify.org?format=json").ip
az network nsg rule update -g rg-microhack-sql-2026 --nsg-name nsg-mh2026 -n Allow-RDP-FromClient --source-address-prefixes $ip
$srv = az sql server list -g rg-microhack-sql-2026 --query "[0].name" -o tsv
az sql server firewall-rule update -g rg-microhack-sql-2026 -s $srv -n AllowClientIp --start-ip-address $ip --end-ip-address $ip
```

---

## 1. Challenge 01 — Assessment

Goal: produce a readiness report + remediation backlog for `TEAM01_AdventureWorks2019`
against **Azure SQL Database** assessment rules.

### 1.1 RDP into the source VM

```powershell
mstsc /v:40.118.6.179
```

Log in as `sqladmin` (password from your creds file). All assessment tooling runs on the VM.

### 1.2 Install Data Migration Assistant (DMA) on the VM

DMA is the supported, lightweight assessment tool (replaces the retired ADS extension).

* Download: <https://www.microsoft.com/en-us/download/details.aspx?id=53595>
* Install with defaults. (Inside the VM, if download is blocked, fetch the MSI on your
  laptop and copy it over the RDP clipboard/drive redirection.)

### 1.3 Run the DMA assessment

1. Open **Data Migration Assistant** → **New (+) → Assessment**.
2. Project type **Assessment**, Source `SQL Server`, Target **`Azure SQL Database`**.
3. Report type: select both **Database compatibility** and **Feature parity**.
4. Connect to source: server `localhost`, **Windows Authentication**
   (you are `sqladmin`, which is now a sysadmin-capable Windows admin context).
   Trust server certificate = yes.
5. Add database **`TEAM01_AdventureWorks2019`** → **Start assessment**.
6. Review findings. Map each to the official rule IDs from
   [assessment rules](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql)
   (e.g. `DbCompatLevelLowerThan100`, `CrossDatabaseReferences`, `LinkedServer`,
   `XpCmdshell`, `AgentJobs`).
7. **Export** the report (JSON/CSV) and keep it with your lab artifacts.

> Because the DB is at **compat 110**, expect at least the low-compat-level finding plus
> any deprecated-feature flags — this is the remediation backlog input for C02.

### 1.4 (Optional, heavier) Azure Migrate SQL assessment

The official challenge also asks for an Azure Migrate appliance-based assessment. For the
**lean** path this is optional — DMA already gives the rule-mapped readiness report. If
you want the SKU + cost recommendation:

* Create an **Azure Migrate** project in `rg-microhack-sql-2026`.
* Deploy the **Azure Migrate appliance** (lightweight installer) **on the source VM**,
  register it, and let it discover + performance-collect the SQL 2019 instance.
* Create an **Azure SQL Database** assessment → capture SKU recommendation, readiness
  category, and monthly cost estimate.
* Reference: <https://learn.microsoft.com/en-us/azure/migrate/concepts-azure-sql-assessment-calculation>

### 1.5 Success criteria (C01)

* [ ] DMA report for `TEAM01_AdventureWorks2019` vs Azure SQL Database, findings mapped to rule IDs.
* [ ] Prioritized remediation backlog (what to fix before C02 vs after).
* [ ] (Optional) Azure Migrate assessment with SKU + cost.
* [ ] Reports exported and stored.

---

## 2. Challenge 02 — DMS offline migration → Azure SQL Database

Goal: migrate `TEAM01_AdventureWorks2019` from the VM to a new empty database on the
target logical server using **Azure Database Migration Service (offline)**.

### 2.1 Pre-migration remediation

Apply the must-fix items from your C01 backlog on the source. At minimum, raising compat
clears the low-compat finding (do this only if your assessment says it is safe):

```sql
-- on the VM, SSMS/sqlcmd against localhost
ALTER DATABASE [TEAM01_AdventureWorks2019] SET COMPATIBILITY_LEVEL = 150;
```

Leave it at 110 if you want to keep demonstrating the finding through the migration.

### 2.2 Register the resource provider + create the empty target DB

```powershell
az provider register --namespace Microsoft.DataMigration
$srv = az sql server list -g rg-microhack-sql-2026 --query "[0].name" -o tsv
# Empty target DB, General Purpose Gen5 2 vCore (baseline per challenge-02)
az sql db create -g rg-microhack-sql-2026 -s $srv -n AdventureWorks2019 `
  --edition GeneralPurpose --family Gen5 --capacity 2 --backup-storage-redundancy Local
```

### 2.3 Provision DMS + Self-hosted Integration Runtime (SHIR)

Use the **Azure SQL Migration** experience (DMS) — portal is simplest for a one-off:

1. Portal → **Azure Database Migration Services** → **Create** → in
   `rg-microhack-sql-2026`, region close to the target (France Central).
2. Create a **new migration project** → Source type `SQL Server`, Target
   `Azure SQL Database`, Migration mode **Offline** (only mode for SQL DB targets).
3. When prompted for the **Self-hosted Integration Runtime**, install SHIR **v5.37+**
   **on the source VM** (`sqlvm-mh2026`) and register it with one of the two keys shown.
   SHIR gives DMS line-of-sight to `localhost` SQL on the VM.

### 2.4 Grant the migration principal on the **Entra-only** target

Because the target is Entra-only, do **not** create a SQL login. Connect to the target
**`master`** as the Entra admin (`admin@MngEnvMCAP872561.onmicrosoft.com`, Microsoft Entra
MFA) and grant the four server-level roles to the Entra principal DMS will use (your admin
UPN works for a self-run lab):

```sql
-- run on TARGET master, connected as the Entra admin
CREATE USER [admin@MngEnvMCAP872561.onmicrosoft.com] FROM EXTERNAL PROVIDER;
ALTER SERVER ROLE [##MS_DatabaseManager##]   ADD MEMBER [admin@MngEnvMCAP872561.onmicrosoft.com];
ALTER SERVER ROLE [##MS_DatabaseConnector##] ADD MEMBER [admin@MngEnvMCAP872561.onmicrosoft.com];
ALTER SERVER ROLE [##MS_DefinitionReader##]  ADD MEMBER [admin@MngEnvMCAP872561.onmicrosoft.com];
ALTER SERVER ROLE [##MS_LoginManager##]      ADD MEMBER [admin@MngEnvMCAP872561.onmicrosoft.com];
```

In the DMS wizard, choose **Microsoft Entra** authentication for the target connection
(interactive/MFA), not SQL auth — SQL auth is blocked by policy.

### 2.5 Run the offline migration

1. In the project, **source** = `localhost` on the VM (via SHIR), Windows auth.
2. Select database **`TEAM01_AdventureWorks2019`** → map to target DB
   **`AdventureWorks2019`**.
3. Enable **Migrate Missing Schema** so DMS deploys schema + data (no separate DACPAC).
4. Start the migration and watch **Monitor migrations** until **Succeeded**.

### 2.6 Validate

From your laptop (VS Code MSSQL / SSMS), connect to the target with **Entra** auth and run:

```sql
SELECT DB_NAME() AS db, COUNT(*) AS people FROM Person.Person;   -- expect ~19,972
SELECT TOP 5 * FROM Sales.SalesOrderHeader ORDER BY SalesOrderID;
```

Compare a couple of row counts against the source VM. Then post-migration housekeeping:

```sql
UPDATE STATISTICS [Person].[Person];      -- example; refresh stats as needed
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 150;
```

### 2.7 Success criteria (C02)

* [ ] `AdventureWorks2019` visible on the target logical server.
* [ ] DMS migration status **Succeeded**.
* [ ] Row counts match source for a representative table.
* [ ] You can `SELECT` from the target with Entra auth (VS Code MSSQL / SSMS).
* [ ] C01 blockers resolved or documented as accepted post-migration work.

---

## 3. Cost hygiene

* VM auto-shuts down daily at **19:00 UTC**. Deallocate manually when done for the day:
  `az vm deallocate -g rg-microhack-sql-2026 -n sqlvm-mh2026`
* DMS instance + SHIR + target DB cost while running — delete DMS and the target DB after
  the lab if you only needed the walkthrough.
* Tear down everything: `az group delete -n rg-microhack-sql-2026 --yes --no-wait`.

---

## 4. Notes vs the official challenges

* The public repo challenges assume **multiple source instances** (SQL 2012 fleet + SQL
  2019/2022 fleet). This lean setup uses **one SQL 2019 VM + AdventureWorks2019** to
  exercise the same C01 (assessment) and C02 (DMS → Azure SQL DB) muscle memory without
  the multi-instance / multi-team scaffolding.
* C03+ (MI Link to Managed Instance) is intentionally **out of scope** — no MI deployed.
* The target being **Entra-only** is specific to this MCAPS subscription's policy; the
  official challenge text uses SQL logins. §2.4 is the adaptation.
