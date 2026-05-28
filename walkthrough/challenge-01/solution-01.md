# Solution 1 — Assessment (2026 edition)

[Previous Solution](../challenge-00/solution-00.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-02/solution-02.md)

## What changed since the original

The original SQL Modernization MicroHack used **Azure Data Studio (ADS)** with the **Azure SQL
Migration extension** to perform assessment and SKU recommendation in a single flow. ADS was
retired on **28-Feb-2026** and the extension is deprecated. This 2026 edition replaces that flow
with two Microsoft-supported tools:

| Original lab choice | 2026 replacement | Why it changed |
|---|---|---|
| Azure Data Studio + SQL Migration extension assessment | **Data Migration Assistant (DMA)** for SQL → Azure SQL DB compatibility | DMA is still supported for Azure SQL DB assessments and produces a familiar findings report. |
| ADS performance collection and SKU recommendation | **Azure Migrate SQL assessment** | Azure Migrate provides discovery, readiness, right-sizing, and cost estimation at scale. |
| One assessment target (MI) | Two assessments — **Azure SQL DB** (for the SQL 2012 source) and **Azure SQL MI** (for the SQL 2019/2022 source) | Different sources require different targets in this edition. |
| Assessment merged with migration in one wizard | Assessment is now its own challenge | Splitting assessment from migration mirrors real customer engagements. |

## Lab architecture for this challenge

This challenge runs **before** any migration. The Azure Migrate appliance lives on the lab
network and reaches both source SQL Server instances. DMA runs locally on the JumpBox against the
SQL Server 2012 source. No Azure SQL target resources are required yet.

**Components used here**

- Resource group: `rg-microhack-sql-2026`
- Region: `westeurope`
- Source 1 (legacy): `vm-sql-2012` running SQL Server 2012 with three application databases
  (referred to in this lab as `app_orders`, `app_inventory`, `app_billing` — confirm the actual
  names in your tenant during Challenge 0)
- Source 2 (modern): `vm-sql-source` running SQL Server 2019/2022 with `AdventureWorks2019` and
  `WideWorldImporters`
- Azure Migrate project: `migrate-microhack-sql-2026`
- Azure Migrate appliance VM: `vm-migrate-appliance`
- DMA workstation: the lab JumpBox

## Prerequisites

- Challenge 0 complete: you can reach both source SQL Server instances from the JumpBox.
- Azure subscription with permission to create Azure Migrate projects, deploy the appliance, and
  read SQL Server metadata.
- Tools on the JumpBox or admin workstation:
  - **Data Migration Assistant** (latest)
  - **Azure CLI 2.60+**
  - **Az PowerShell 11+**
  - **SSMS 20+**
  - **VS Code** with the MSSQL extension
- SQL Server credentials with at least sysadmin-equivalent assessment rights on both source
  instances.

Sign in:

```bash
az login --tenant <tenant-id>
az account set --subscription "<subscription-id>"
```

```powershell
Connect-AzAccount -Tenant "<tenant-id>"
Set-AzContext -Subscription "<subscription-id>"
```

---

## Step 1 — DMA assessment for the SQL Server 2012 source

DMA is the right tool to assess SQL Server 2012 databases against Azure SQL Database. It
produces feature parity, compatibility, and breaking-change findings that you will use in
Challenge 2 to plan the DMS migration.

### 1.1 Install and launch DMA

1. On the JumpBox, download and install the latest [Data Migration Assistant](https://www.microsoft.com/en-us/download/details.aspx?id=53595).
2. Launch DMA and select **New** (`+`) → **Assessment**.

### 1.2 Configure the assessment project

Use these settings for the SQL 2012 → Azure SQL Database scenario:

| Setting | Value |
|---|---|
| Project type | Assessment |
| Source server type | SQL Server |
| Target server type | Azure SQL Database |
| Project name | `microhack-sql2012-to-azuresqldb` |

Report types to enable:

- **Check database compatibility**
- **Check feature parity**

### 1.3 Connect to the SQL Server 2012 source

1. Provide the SQL 2012 host name (for example `vm-sql-2012.contoso.local,1433`) and SQL
   authentication credentials captured in Challenge 0.
2. Select the three application databases (`app_orders`, `app_inventory`, `app_billing` — use the
   real names from Challenge 0).
3. Start the assessment.

### 1.4 Review and export findings

DMA produces three buckets:

- **Migration blockers** — features not supported on Azure SQL Database (e.g. SQL Agent jobs,
  cross-database queries without elastic queries, CLR with `EXTERNAL_ACCESS`, FileStream).
- **Behavior changes** — features that exist but behave differently.
- **Information** — deprecated features that still work today.

Steps:

1. Open each database tab and review findings per bucket.
2. For each blocker, decide:
   - **Fix on source before migration** (preferred for breaking changes).
   - **Refactor on target after migration** (acceptable for deprecated features).
   - **Re-platform to a different target** (e.g. Managed Instance) if a critical blocker cannot
     be removed.
3. Export the report: **Export report** → save as JSON and CSV next to the lab artifacts.

> Keep the DMA report — Challenge 2 references it when you build the DMS migration project.

---

## Step 2 — Create the Azure Migrate project

Azure Migrate replaces the ADS SKU recommendation experience and handles **both** source
profiles in a single project.

1. In the Azure portal, search for **Azure Migrate** and open the hub.
2. Select **Create project**.
3. Configure:
   - Subscription: lab subscription
   - Resource group: `rg-microhack-sql-2026`
   - Project name: `migrate-microhack-sql-2026`
   - Geography: Europe

CLI helper for automation runs:

```bash
az migrate project create \
  --resource-group rg-microhack-sql-2026 \
  --name migrate-microhack-sql-2026 \
  --location westeurope
```

---

## Step 3 — Deploy the Azure Migrate appliance

The appliance discovers SQL Server inventory, configuration, and performance counters from both
the SQL 2012 and SQL 2019/2022 instances.

1. From the Azure Migrate project, open **Discover and assess** → **Discover**.
2. Choose **SQL Server**, then **Using appliance**.
3. Select **Servers running in your VMware environment / Physical or other servers** depending on
   your lab topology. For an Azure-hosted simulated on-prem, **Physical or other** is the right
   choice.
4. Download the appliance configuration file and the appliance installer.
5. Provision a Windows Server VM in the lab network (`vm-migrate-appliance`, `Standard_D4s_v3`
   recommended) and run the installer there.
6. Open the appliance configuration manager (`https://<appliance-name>:44368`) and:
   - Sign in to the Azure subscription
   - Add **SQL Server authentication credentials** with read access to system DMVs on each source
     instance
   - Add the IPs / FQDNs of both source instances
   - Start **Continuous discovery**

Allow at least 15–30 minutes of performance collection so the SKU recommendation has enough
samples. For real engagements collect 7–30 days.

---

## Step 4 — Run the assessment for SQL Server 2012 → Azure SQL Database

1. In the Azure Migrate project, open **Discover and assess** → **Assess**.
2. Choose **Azure SQL** as the assessment type.
3. Configure assessment **properties**:
   - Name: `assess-sql2012-to-azuresqldb`
   - **Target deployment type**: Azure SQL Database
   - **Service tier**: General Purpose
   - **Compute tier**: Provisioned
   - **Pricing model**: Pay-as-you-go (or your reservation choice)
   - **Sizing criteria**: Performance-based (fallback: as-on-premises) — comfort factor 1.2 for
     lab, 1.5+ for production
   - Region: `westeurope`
4. Select the discovered group containing `vm-sql-2012` and run the assessment.
5. When the run completes, open the assessment and capture:
   - **Migration readiness** for each of the three databases
   - **SKU recommendation** (vCore size, storage, estimated monthly cost)
   - **Migration issues** and **Migration warnings**
6. Export results: **Export assessment** → download the Excel report.

Expected pattern for a vanilla SQL 2012 lab:

| Database | Readiness | Likely SKU | Notes |
|---|---|---|---|
| `app_orders` | Ready with conditions | GP Gen5 2 vCore | Watch for cross-DB queries |
| `app_inventory` | Ready | GP Gen5 2 vCore | Clean |
| `app_billing` | Ready with conditions | GP Gen5 4 vCore | SQL Agent jobs flagged |

(Adjust based on the actual lab tenant data — the numbers above are illustrative.)

---

## Step 5 — Run the assessment for SQL Server 2019/2022 → Azure SQL Managed Instance

1. Repeat the assessment flow with a new assessment named `assess-sql2019-to-azuresqlmi`.
2. Configure properties:
   - **Target deployment type**: Azure SQL Managed Instance
   - **Service tier**: General Purpose
   - **Compute tier**: Provisioned
   - **Pricing model**: Pay-as-you-go
   - **Sizing criteria**: Performance-based
   - Region: `westeurope`
3. Select the discovered group containing `vm-sql-source` (the SQL 2019/2022 host) and run the
   assessment.
4. Capture:
   - **Migration readiness** for `AdventureWorks2019` and `WideWorldImporters`
   - **SKU recommendation** (target General Purpose, ~4 vCore, ~32 GB+ storage)
   - **Monthly cost estimate** (used as the baseline for Challenge 3)

---

## Step 6 — Build the remediation backlog

Combine DMA and Azure Migrate findings into a single backlog. Use this table as a template:

| Finding | Source DB | Severity | Decision | Owner | Target challenge |
|---|---|---|---|---|---|
| SQL Agent job uses xp_cmdshell | `app_billing` (SQL 2012) | Blocker | Refactor to Azure Automation runbook | DBA | Before Challenge 2 |
| Cross-database query | `app_orders` (SQL 2012) | Blocker | Move shared table or use elastic query | App team | Before Challenge 2 |
| Deprecated DB compatibility level 100 | `app_inventory` (SQL 2012) | Info | Raise compat level on target after migration | DBA | After Challenge 2 |
| CLR assembly EXTERNAL_ACCESS | `WideWorldImporters` | Blocker for SQL DB, OK for MI | Stay on MI path | Architect | Confirms Challenge 3 target |
| SQL Server 2019 trace flag 4199 | `vm-sql-source` instance | Info | Enable matching MI feature flag post-migration | DBA | After Challenge 3 |

Persist this backlog as `assessment-backlog.md` (or a sheet) next to the exported assessment
reports.

---

## Success criteria checklist

- [ ] DMA report produced for the SQL 2012 source (3 databases, Azure SQL DB target)
- [ ] Azure Migrate project `migrate-microhack-sql-2026` exists
- [ ] Appliance is connected and discovery shows both source instances
- [ ] Assessment `assess-sql2012-to-azuresqldb` complete with SKU recommendation
- [ ] Assessment `assess-sql2019-to-azuresqlmi` complete with SKU recommendation
- [ ] Remediation backlog written and committed alongside lab artifacts
- [ ] All findings used to plan Challenge 2 (DMS) and Challenge 3 (MI Link)

---

## Annex — Useful T-SQL discovery queries

Run these on each source instance to sanity-check the appliance findings:

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

-- SQL Agent jobs (Azure SQL DB does not support SQL Agent)
USE msdb;
SELECT name, enabled, date_created FROM dbo.sysjobs;

-- Linked servers (not supported on Azure SQL DB)
SELECT name, product, provider, data_source FROM sys.servers WHERE server_id > 0;

-- CLR assemblies
SELECT name, permission_set_desc, is_user_defined FROM sys.assemblies WHERE is_user_defined = 1;

-- Cross-database references
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
