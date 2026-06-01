# Solution 1 — Assessment (2026 edition)

[Previous Solution](../challenge-00/solution-00.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-02/solution-02.md)

## What changed since the original

The original SQL Modernization MicroHack used **Azure Data Studio (ADS)** with the **Azure SQL
Migration extension** to assess and size in one flow. ADS was retired on **28-Feb-2026** and the
extension is deprecated. This 2026 edition uses **Data Migration Assistant (DMA)** — the
Microsoft-supported, lightweight assessment tool for **SQL Server → Azure SQL Database**.

| Original lab choice | 2026 replacement | Why |
|---|---|---|
| Azure Data Studio + SQL Migration extension | **Data Migration Assistant (DMA)** | Still supported for Azure SQL DB assessments; produces a familiar rule-mapped findings report. |
| Assessment merged with migration in one wizard | Assessment is its **own** challenge | Splitting assessment from migration mirrors real customer engagements. |
| Multi-instance fleet (SQL 2012 + SQL 2019/2022) | **Single SQL Server 2019 source** | This walkthrough runs the real lean lab: one IaaS VM → one Azure SQL Database. No Azure Migrate appliance, no Managed Instance. |

> **Scope of this walkthrough.** Challenge 1 (assessment) and Challenge 2 (DMS migration) run
> against **one** SQL Server 2019 IaaS VM and **one** empty Azure SQL Database target. The
> appliance-based Azure Migrate SKU/cost flow is documented as an **optional** add-on at the end —
> it is not required to complete the challenge.

## Lab architecture for this challenge

Everything lives in one resource group, `rg-microhack-sql-2026`. The source SQL Server runs on an
IaaS VM; the empty Azure SQL logical server is the migration target you will fill in Challenge 2.

![Resource group rg-microhack-sql-2026 — all lab resources](../../Images/c1-step-01-resource-group.png)

| Component | Name | Notes |
|---|---|---|
| Resource group | `rg-microhack-sql-2026` | West Europe |
| Source VM | `sqlvm-mh2026` | SQL Server 2019 Developer on Windows Server 2022, `Standard_D4s_v5` |
| Source NSG | `nsg-mh2026` | RDP 3389 from your client IP only; 1433 intra-VNet |
| VNet / subnet | `vnet-mh2026` / `snet-sql` | `10.0.0.0/16` / `10.0.1.0/24` |
| Bastion | `bastion-mh2026` | Secure browser RDP to the VM (no public RDP needed) |
| **Migration target** | `sqlsrvmh2026tin4vcwzqrg3k` | Azure SQL logical server, **France Central**, **Entra-only auth** (empty until Challenge 2) |

### The source instance

`sqlvm-mh2026` runs SQL Server 2019 with a set of restored sample databases used for both
challenges:

![sqlvm-mh2026 — virtual machine overview](../../Images/c1-step-02-source-vm.png)

| Database | Based on | Compat level | Why it's interesting for assessment |
|---|---|---|---|
| `TEAM99_LocalMasterDataDB` | AdventureWorks2019 (OLTP) | 120 (SQL 2014) | Classic OLTP schema; clean baseline. |
| `TEAM99_SharedMasterDatabDB` | WideWorldImporters (OLTP) | 120 (SQL 2014) | Uses **In-Memory OLTP (memory-optimized tables)** — a real tier-impacting finding. |
| `TEAM99_TenantDataDB` | AdventureWorksDW2019 (data warehouse) | 120 (SQL 2014) | Star schema + columnstore. |
| `TEAM01_AdventureWorks2019` | AdventureWorks2019 (OLTP) | 110 (SQL 2008 R2) | Intentionally low compat level to surface a compatibility advisory. |

> The databases sit at **compat 110/120**, below the current Azure SQL Database default. Both are
> *supported* on Azure SQL Database, so this is an **advisory** (raise the compat level post-migration),
> not a blocker — DMA will flag it accordingly.

## Prerequisites

- Challenge 0 complete: the lab resource group is deployed and you can reach the VM.
- Azure subscription with read access to the resource group and permission to use Bastion.
- Tools (installed **on the source VM**, where the assessment runs):
  - **Data Migration Assistant** (latest)
  - **SSMS 20+** (optional, to eyeball the databases)
- SQL Server admin rights on the source instance (the `sqladmin` Windows account is a sysadmin
  context on the VM).

Sign in to Azure if you want to inspect resources from CLI:

```bash
az login --tenant <tenant-id>
az account set --subscription "<subscription-id>"
```

---

## Step 1 — Connect to the source VM with Bastion

All assessment tooling (DMA) runs **on the VM**. Use **Azure Bastion** for a secure, browser-based
RDP session — no public RDP port required.

1. Open the VM `sqlvm-mh2026` → **Connect** → **Bastion**.
2. Confirm **Using Bastion: bastion-mh2026** shows **Provisioning State: Succeeded**.
3. Authentication type **VM Password**, enter the VM username/password, then **Connect**.

![Bastion connect blade for sqlvm-mh2026](../../Images/c1-step-04-bastion-connect.png)

> **Alternative:** if your client IP is allowed on `nsg-mh2026`, you can RDP directly with
> `mstsc /v:<vm-public-ip>`. Bastion is preferred because it needs no inbound RDP from the internet.

---

## Step 2 — DMA assessment against Azure SQL Database

DMA evaluates the source databases against the official
[**assessment rules for SQL Server → Azure SQL Database**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql)
and produces feature-parity and compatibility findings you will use in Challenge 2.

### 2.1 Install and launch DMA

1. On the VM, download and install the latest
   [Data Migration Assistant](https://www.microsoft.com/en-us/download/details.aspx?id=53595)
   (if the in-VM download is blocked, fetch the MSI on your laptop and paste it over the Bastion
   clipboard / drive redirection).
2. Launch DMA and select **New** (`+`) → **Assessment**.

### 2.2 Configure the assessment project

| Setting | Value |
|---|---|
| Project type | Assessment |
| Source server type | SQL Server |
| Target server type | **Azure SQL Database** |
| Project name | `microhack-assessment` |

Report types to enable:

- **Check database compatibility**
- **Check feature parity**

### 2.3 Connect to the source and select databases

1. Server: `localhost` — **Windows Authentication** (you are `sqladmin`, a sysadmin context).
   Set **Trust server certificate = Yes**.
2. Select the databases in scope:
   - `TEAM99_LocalMasterDataDB`
   - `TEAM99_SharedMasterDatabDB`
   - `TEAM99_TenantDataDB`
   - `TEAM01_AdventureWorks2019`
3. **Start assessment**.

### 2.4 Review and export findings

Each finding has a **rule ID**, a **level** (`Database` or `Instance`), and a **category**
(`Issue` for blockers, `Warning` for behaviour changes). For these sample databases the realistic
findings are:

| Rule / finding | Level | Category | Applies to | What it means / decision |
|---|---|---|---|---|
| **Memory-optimized tables (In-Memory OLTP)** | Database | Issue | `TEAM99_SharedMasterDatabDB` (WideWorldImporters) | In-Memory OLTP is only available on Azure SQL Database **Business Critical / Premium** tiers — *not* General Purpose. Either choose a BC/Premium target tier, or drop/convert the memory-optimized tables before migrating to General Purpose. |
| **Compatibility level below current default** | Database | Warning | All four DBs (110/120) | Supported, but below the latest default. Raise with `ALTER DATABASE … SET COMPATIBILITY_LEVEL` **after** cut-over once you've validated behaviour. |
| `AgentJobs` | Instance | Warning | Instance | SQL Server Agent jobs aren't available in Azure SQL DB; move to Elastic Jobs or Azure Automation. (Fires only if you've created Agent jobs.) |
| `WindowsAuthentication` | Instance | Warning | Instance | Windows-auth logins aren't supported; the target uses **Microsoft Entra ID**. |
| `LinkedServer` / `CrossDatabaseReferences` / `XpCmdshell` / `ServiceBroker` / `ClrAssemblies` | Database | Issue | (none expected) | Hard blockers on Azure SQL DB. The stock AdventureWorks / WideWorldImporters / DW samples don't use them, so they should **not** fire here — but this is exactly the catalogue you check against on a real customer database. |

For every finding decide:

- **Fix on source before migration** (preferred for `Issue` blockers).
- **Refactor on target after migration** (acceptable for some `Warning` items, e.g. raising the
  compat level post-cutover).
- **Choose a different target tier** when a feature is tier-gated (e.g. pick Business Critical to
  keep In-Memory OLTP).

Then:

1. Open each database tab and review findings per category.
2. **Export report** → save as JSON and CSV next to your lab artifacts.

> Keep the DMA report — Challenge 2 references it when you build the DMS migration project. The full
> rule catalogue is in the official
> [assessment rules article](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql).

---

## Step 3 — Review the migration target

Challenge 2 migrates a source database into the empty Azure SQL logical server already deployed in
the resource group. Note its properties now so the migration step is smooth:

![Azure SQL logical server sqlsrvmh2026tin4vcwzqrg3k — overview](../../Images/c1-step-03-sql-target.png)

| Property | Value | Why it matters for Challenge 2 |
|---|---|---|
| Server name | `sqlsrvmh2026tin4vcwzqrg3k.database.windows.net` | Target FQDN for DMS. |
| Location | France Central | Provision DMS in/near this region. |
| Authentication | **Microsoft Entra-only** | **Key gotcha:** you cannot create a SQL login. DMS must connect to the target with **Microsoft Entra** auth, and the migration principal needs the `##MS_*##` server roles (see Challenge 2). |
| Entra admin | `admin@MngEnvMCAP872561.onmicrosoft.com` | The identity used to grant the migration principal. |
| Databases | none yet | The target is empty — Challenge 2 creates the destination database and migrates into it. |

---

## Step 4 — Build the remediation backlog

Turn the DMA findings into a prioritized backlog. Tag each row with the **official rule name** so
reviewers can trace every item back to the
[assessment rules article](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql).

| Finding | Source DB | Category | Decision | When |
|---|---|---|---|---|
| Memory-optimized tables | `TEAM99_SharedMasterDatabDB` | Issue | Choose Business Critical target tier **or** convert the memory-optimized tables to disk-based before migrating to General Purpose | Before Challenge 2 |
| Compat level 110 | `TEAM01_AdventureWorks2019` | Warning | Raise compat level on the target after migration once validated | After Challenge 2 |
| Compat level 120 | `TEAM99_*` | Warning | Raise compat level post-cutover | After Challenge 2 |
| `WindowsAuthentication` | instance | Warning | Re-create needed principals as Microsoft Entra users on the target | During Challenge 2 |

Persist this backlog as `assessment-backlog.md` (or a sheet) next to the exported DMA report.

---

## Step 5 — (Optional) Azure Migrate SKU & cost recommendation

DMA gives you the rule-mapped readiness report, which is enough to proceed to Challenge 2. If you
also want a **SKU recommendation and monthly cost estimate**, run an Azure Migrate SQL assessment.
This is **optional** and heavier (it needs the lightweight appliance):

1. Create an **Azure Migrate** project in `rg-microhack-sql-2026`.
2. Deploy the **Azure Migrate appliance** (lightweight installer) **on the source VM**, register
   it, and let it discover + performance-collect the SQL 2019 instance (allow 15–30 min of
   collection in the lab; 7–30 days for real engagements).
3. Create an **Azure SQL Database** assessment and capture the **readiness category**, **SKU
   recommendation** (vCore size, storage), and **monthly cost estimate**.
4. Reference:
   [Azure Migrate assessment for Azure SQL](https://learn.microsoft.com/en-us/azure/migrate/concepts-azure-sql-assessment-calculation).

---

## Success criteria checklist

- [ ] You connected to `sqlvm-mh2026` (Bastion or RDP).
- [ ] DMA assessment produced against **Azure SQL Database** for the in-scope databases, with
      findings mapped to official rule IDs.
- [ ] Tier-impacting finding (In-Memory OLTP in `TEAM99_SharedMasterDatabDB`) identified and a target
      decision recorded.
- [ ] Prioritized remediation backlog written (fix-before vs fix-after Challenge 2).
- [ ] DMA report exported and stored with the lab artifacts.
- [ ] (Optional) Azure Migrate assessment with SKU + monthly cost captured.

---

## Annex — Useful T-SQL discovery queries

Run these on the source instance (`localhost` on the VM) to sanity-check the DMA findings:

```sql
-- Databases, size, recovery model, compat level
SELECT
    d.name,
    d.database_id,
    d.state_desc,
    d.recovery_model_desc,
    d.compatibility_level,
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(10,2)) AS size_mb
FROM sys.databases d
JOIN sys.master_files mf ON d.database_id = mf.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.database_id, d.state_desc, d.recovery_model_desc, d.compatibility_level
ORDER BY size_mb DESC;

-- Memory-optimized (In-Memory OLTP) tables — tier-gated on Azure SQL Database
SELECT DB_NAME() AS db, COUNT(*) AS memory_optimized_tables
FROM sys.tables WHERE is_memory_optimized = 1;

-- SQL Agent jobs (not supported on Azure SQL DB)
USE msdb;
SELECT name, enabled, date_created FROM dbo.sysjobs;

-- Linked servers (not supported on Azure SQL DB)
SELECT name, product, provider, data_source FROM sys.servers WHERE server_id > 0;

-- CLR assemblies (not supported on Azure SQL DB)
SELECT name, permission_set_desc, is_user_defined FROM sys.assemblies WHERE is_user_defined = 1;

-- Cross-database references (not supported on Azure SQL DB)
SELECT DISTINCT
    referencing_schema_name = OBJECT_SCHEMA_NAME(d.referencing_id),
    referencing_object_name = OBJECT_NAME(d.referencing_id),
    referenced_database_name = d.referenced_database_name
FROM sys.sql_expression_dependencies d
WHERE d.referenced_database_name IS NOT NULL
  AND d.referenced_database_name <> DB_NAME();
```

---

[Previous Solution](../challenge-00/solution-00.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-02/solution-02.md)
