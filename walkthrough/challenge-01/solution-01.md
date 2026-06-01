# Solution 1 — Assessment (2026 edition)

[Previous Solution](../challenge-00/solution-00.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-02/solution-02.md)

## What changed since the original

The original SQL Modernization MicroHack used **Azure Data Studio (ADS)** with the **Azure SQL
Migration extension** to assess and size in one flow. ADS was retired on **28-Feb-2026** and the
extension is deprecated. The **Data Migration Assistant (DMA)** that earlier editions fell back on
is **also retired (16-Jul-2025)** and is no longer available to download.

Per the official
[**SQL Server → Azure SQL Database migration guidance**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql#migration-tools),
this 2026 edition uses **Azure Migrate** for the assessment (readiness, migration blockers/warnings,
SKU recommendation and monthly cost) and **Azure Database Migration Service (DMS)** for the migration
in Challenge 2.

| Original lab choice | 2026 replacement | Why |
|---|---|---|
| Azure Data Studio + SQL Migration extension | **Azure Migrate (Azure SQL assessment)** | ADS retired (28-Feb-2026). Azure Migrate is the current Microsoft-recommended assessment tool and produces the readiness + rule-mapped findings, plus SKU and cost. |
| Data Migration Assistant (DMA) | **Azure Migrate** | DMA is **retired (16-Jul-2025)** and can no longer be downloaded; its readiness assessment is superseded by Azure Migrate. |
| Assessment merged with migration in one wizard | Assessment is its **own** challenge | Splitting assessment from migration mirrors real customer engagements. |
| Multi-instance fleet (SQL 2012 + SQL 2019/2022) | **Single SQL Server 2019 source** | This walkthrough runs the real lean lab: one IaaS VM → one Azure SQL Database. No Managed Instance, no fleet. |

> **Scope of this walkthrough.** Challenge 1 (assessment) and Challenge 2 (DMS migration) run
> against **one** SQL Server 2019 IaaS VM and **one** empty Azure SQL Database target. Azure Migrate
> uses a lightweight appliance on the source VM; in this lab a short discovery window is enough — you
> do **not** need the multi-day performance collection used in real engagements.

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
> not a blocker — Azure Migrate flags it accordingly.

## Prerequisites

- Challenge 0 complete: the lab resource group is deployed and you can reach the VM.
- Azure subscription with read access to the resource group and permission to use Bastion and to
  create an **Azure Migrate** project.
- Tools (installed **on the source VM**, where discovery runs):
  - **Azure Migrate appliance** (lightweight installer, downloaded from the Azure Migrate project)
  - **SSMS 20+** (optional, to eyeball the databases)
- SQL Server admin rights on the source instance (the `sqladmin` Windows account is a sysadmin
  context on the VM), used by the appliance to read SQL metadata.

Sign in to Azure if you want to inspect resources from CLI:

```bash
az login --tenant <tenant-id>
az account set --subscription "<subscription-id>"
```

---

## Step 1 — Connect to the source VM with Bastion

All assessment tooling runs **from Azure** (the Azure Migrate appliance sits **on the VM**). Use
**Azure Bastion** for a secure, browser-based RDP session to deploy and register the appliance — no
public RDP port required.

1. Open the VM `sqlvm-mh2026` → **Connect** → **Bastion**.
2. Confirm **Using Bastion: bastion-mh2026** shows **Provisioning State: Succeeded**.
3. Authentication type **VM Password**, enter the VM username/password, then **Connect**.

![Bastion connect blade for sqlvm-mh2026](../../Images/c1-step-04-bastion-connect.png)

> **Alternative:** if your client IP is allowed on `nsg-mh2026`, you can RDP directly with
> `mstsc /v:<vm-public-ip>`. Bastion is preferred because it needs no inbound RDP from the internet.

---

## Step 2 — Azure Migrate assessment against Azure SQL Database

Azure Migrate discovers the source SQL Server instance and evaluates its databases against the
official
[**assessment rules for SQL Server → Azure SQL Database**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql),
producing a **readiness** result (with migration blockers and warnings), a **SKU recommendation**,
and a **monthly cost estimate** you will use in Challenge 2.

### 2.1 Create the Azure Migrate project and discover the source

1. In the portal, create an **Azure Migrate** project in `rg-microhack-sql-2026` (or reuse one).
2. Under **Migration and modernization** → **Discover**, choose to discover **SQL Server instances
   and databases**, and download the **Azure Migrate appliance** installer.
3. On the VM (via Bastion), run the installer, **register the appliance** with the project, and add
   the SQL connection: server `localhost`, **Windows / integrated** auth (you are `sqladmin`, a
   sysadmin context). Trust the server certificate.
4. Let the appliance **discover** the instance and start collecting. In this lab a short window
   (15–30 min) is enough; real engagements collect performance data for 7–30 days for accurate
   right-sizing.

### 2.2 Create the Azure SQL Database assessment

1. In the Azure Migrate project, open **Assessments** → **Create assessment**.
2. Assessment type: **Azure SQL Database**.
3. Add the in-scope databases:
   - `TEAM99_LocalMasterDataDB`
   - `TEAM99_SharedMasterDatabDB`
   - `TEAM99_TenantDataDB`
   - `TEAM01_AdventureWorks2019`
4. Review the sizing criteria (performance-based vs as-on-premises) and create the assessment.

### 2.3 Review readiness findings

Azure Migrate reports each database as **Ready**, **Ready with conditions**, or **Not ready**, and
maps each issue to the same official rule catalogue (a **migration blocker** or a **warning**). For
these sample databases the realistic findings are:

| Rule / finding | Severity | Applies to | What it means / decision |
|---|---|---|---|
| **Memory-optimized tables (In-Memory OLTP)** | Blocker / tier-gated | `TEAM99_SharedMasterDatabDB` (WideWorldImporters) | In-Memory OLTP is only available on Azure SQL Database **Business Critical / Premium** tiers — *not* General Purpose. Either choose a BC/Premium target tier, or drop/convert the memory-optimized tables before migrating to General Purpose. |
| **Compatibility level below current default** | Warning | All four DBs (110/120) | Supported, but below the latest default. Raise with `ALTER DATABASE … SET COMPATIBILITY_LEVEL` **after** cut-over once you've validated behaviour. |
| `AgentJobs` | Warning (instance) | Instance | SQL Server Agent jobs aren't available in Azure SQL DB; move to Elastic Jobs or Azure Automation. (Fires only if you've created Agent jobs.) |
| `WindowsAuthentication` | Warning (instance) | Instance | Windows-auth logins aren't supported; the target uses **Microsoft Entra ID**. |
| `LinkedServer` / `CrossDatabaseReferences` / `XpCmdshell` / `ServiceBroker` / `ClrAssemblies` | Blocker | (none expected) | Hard blockers on Azure SQL DB. The stock AdventureWorks / WideWorldImporters / DW samples don't use them, so they should **not** fire here — but this is exactly the catalogue you check against on a real customer database. |

For every finding decide:

- **Fix on source before migration** (preferred for blockers).
- **Refactor on target after migration** (acceptable for some warnings, e.g. raising the compat
  level post-cutover).
- **Choose a different target tier** when a feature is tier-gated (e.g. pick Business Critical to
  keep In-Memory OLTP).

### 2.4 Capture SKU recommendation and cost

Azure Migrate also returns a **recommended Azure SQL Database SKU** (service tier, vCores, storage)
and a **monthly cost estimate** for each database. Record these next to the readiness findings — you
will pick the target tier in Challenge 2 (remember In-Memory OLTP forces **Business Critical**).

> Keep the assessment export — Challenge 2 references it when you build the DMS migration project.
> The full rule catalogue is in the official
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

Turn the Azure Migrate readiness findings into a prioritized backlog. Tag each row with the
**official rule name** so reviewers can trace every item back to the
[assessment rules article](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql).

| Finding | Source DB | Severity | Decision | When |
|---|---|---|---|---|
| Memory-optimized tables | `TEAM99_SharedMasterDatabDB` | Blocker | Choose Business Critical target tier **or** convert the memory-optimized tables to disk-based before migrating to General Purpose | Before Challenge 2 |
| Compat level 110 | `TEAM01_AdventureWorks2019` | Warning | Raise compat level on the target after migration once validated | After Challenge 2 |
| Compat level 120 | `TEAM99_*` | Warning | Raise compat level post-cutover | After Challenge 2 |
| `WindowsAuthentication` | instance | Warning | Re-create needed principals as Microsoft Entra users on the target | During Challenge 2 |

Persist this backlog as `assessment-backlog.md` (or a sheet) next to the exported Azure Migrate
assessment.

---

## Step 5 — (Optional) Command-line assessment without the appliance

If you don't want to deploy the Azure Migrate appliance, you can run an assessment from the command
line with the **`Az.DataMigration` PowerShell module / `az datamigration` Azure CLI**, which uses the
same rule engine. This is **optional** and produces the rule-mapped readiness findings (without the
SKU/cost sizing that Azure Migrate adds):

1. Install the extension: `az extension add --name datamigration`.
2. Run the SQL assessment against the local instance and export the report to JSON/CSV.
3. Reference:
   [Migrate databases at scale using automation (PowerShell / Azure CLI)](https://learn.microsoft.com/en-us/azure/dms/migration-dms-powershell-cli).

---

## Success criteria checklist

- [ ] You connected to `sqlvm-mh2026` (Bastion or RDP) and registered the Azure Migrate appliance.
- [ ] Azure Migrate **Azure SQL Database** assessment produced for the in-scope databases, with
      findings mapped to official rule IDs.
- [ ] Tier-impacting finding (In-Memory OLTP in `TEAM99_SharedMasterDatabDB`) identified and a target
      decision recorded.
- [ ] SKU recommendation and monthly cost estimate captured per database.
- [ ] Prioritized remediation backlog written (fix-before vs fix-after Challenge 2).
- [ ] Assessment report exported and stored with the lab artifacts.

---

## Annex — Useful T-SQL discovery queries

Run these on the source instance (`localhost` on the VM) to sanity-check the Azure Migrate findings:

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
