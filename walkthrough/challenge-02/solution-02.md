# Solution 2 — DMS migration: SQL Server 2019 → Azure SQL Database (2026 edition)

[Previous Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-03/solution-03.md)

> This walkthrough follows the official Microsoft tutorial
> [**Migrate SQL Server to Azure SQL Database (offline) with Database Migration Service**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service?view=azuresql)
> and the
> [**SQL Server to Azure SQL Database migration guide**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql).
> Where the lab departs from the tutorial (three `TEAM99_*` databases instead of
> `AdventureWorks2022`, a SQL 2019 source, and an **Entra-only** target) the changes are called out
> inline.

## What changed since the original

The original SQL Modernization MicroHack migrated databases through the Azure Data Studio (ADS)
SQL Migration extension. ADS was retired on **28-Feb-2026**. This 2026 edition rebuilds the
migration path on top of **Azure Database Migration Service (DMS)**, driven end-to-end from the
**Azure portal**, with the **Migrate Missing Schema** option of DMS deploying schema and data
in a single migration project — the supported Microsoft-native flow for SQL Server → Azure
SQL Database.

| Original lab choice | 2026 replacement | Why it changed |
|---|---|---|
| ADS + Azure SQL Migration extension | **Azure Database Migration Service** (driven from the Azure portal) | ADS is retired; DMS is the underlying service and remains supported. |
| Implicit runtime managed by ADS | DMS connects through a **self-hosted integration runtime (SHIR)** | For the **Azure SQL Database** target the portal **disables the scenario until a SHIR is connected** — even when the source is an Azure VM. You register one in Step 3.2 (download installer + paste auth key; no CLI). See [Self-hosted Integration Runtime](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service). |
| SQL Server 2019/2022 source | **SQL Server 2019** source (the Challenge 1 IaaS VM) | Same source instance assessed in Challenge 1 — one IaaS VM, no fleet. |
| Two sample databases (`AdventureWorks2019`, `WideWorldImporters`) | **Three `TEAM99_*` databases** (`TEAM99_LocalMasterDataDB`, `TEAM99_SharedMasterDatabDB`, `TEAM99_TenantDataDB`) | The exact databases restored on the lab VM and assessed in Challenge 1. |
| Target Azure SQL Managed Instance | **Azure SQL Database** (single databases on one logical server) | Matches the empty Entra-only logical server already deployed for this lab. |
| Schema and data migrated in one wizard step | Schema and data migrated in one wizard step via the **Migrate Missing Schema** checkbox in DMS | Confirmed by the official DMS tutorial. SqlPackage / DACPAC remains a supported alternative (see Annex D). |

> **Online migration is not available for Azure SQL Database targets.** Application downtime
> starts when the DMS migration starts. Plan an offline cut-over window.

## Lab architecture for this challenge

```
+----------------------------+      via SHIR        +---------------------------+
|  sqlvm-mh2026              |  <----------------->  |  Azure Database           |
|  (SQL Server 2019 Dev)     |                       |  Migration Service        |
|                            |                       |  (microhacksqlmigration)  |
|  TEAM99_LocalMasterDataDB  |                       +-------------+-------------+
|  TEAM99_SharedMasterDatabDB|                                     |
|  TEAM99_TenantDataDB       |                                     v
+----------------------------+        +-----------------------------------------------+
                                      |  Azure SQL logical server                     |
                                      |  sqlsrvmh2026tin4vcwzqrg3k (Entra-only)       |
                                      |                                               |
                                      |  TEAM99_LocalMasterDataDB   (General Purpose) |
                                      |  TEAM99_SharedMasterDatabDB (Business Critical|
                                      |                              — In-Memory OLTP)|
                                      |  TEAM99_TenantDataDB        (General Purpose) |
                                      +-----------------------------------------------+
```

**Components**

- Resource group: `rg-microhack-sql-2026`
- Region: `francecentral` (matches the target logical server)
- Source: `sqlvm-mh2026` (SQL Server 2019 Developer, the Challenge 1 VM, three `TEAM99_*` databases)
- Target logical server: `sqlsrvmh2026tin4vcwzqrg3k.database.windows.net` (**Microsoft Entra-only auth**)
- Target databases (created empty before migration): `TEAM99_LocalMasterDataDB`,
  `TEAM99_SharedMasterDatabDB` (**Business Critical** — In-Memory OLTP), `TEAM99_TenantDataDB`
- DMS instance: `microhacksqlmigration`
- Connectivity: DMS reaches the source through a **self-hosted integration runtime (SHIR)** — the
  Azure SQL Database scenario requires it (registered in Step 3.2 from the portal; no CLI).

## Prerequisites

### Azure access

You can use either built-in roles or the custom DMS role from the
[official custom roles article](https://learn.microsoft.com/en-us/data-migration/sql-server/database/custom-roles?view=azuresql).

**Option A — built-in roles** (as listed in the DMS tutorial):

- **Contributor** on the target Azure SQL Database (logical server scope).
- **Reader** on the resource group that contains the target Azure SQL Database.
- **Owner** or **Contributor** on the subscription **if you need to create the DMS instance**.

**Option B — custom role** (least-privilege, recommended for production): create a custom role
that grants only the DMS + SQL actions documented in
[custom-roles](https://learn.microsoft.com/en-us/data-migration/sql-server/database/custom-roles?view=azuresql).
The full JSON is in **Annex E** of this walkthrough.

### Source SQL Server 2019 permissions

The login that DMS uses to connect to the source must be a member of the **`db_datareader`**
role on each migrated database. For **schema migration via DMS** the login must be **`db_owner`**
on each source database.

### Target Azure SQL Database permissions

> **Key gotcha — the target is Microsoft Entra-only.** The logical server
> `sqlsrvmh2026tin4vcwzqrg3k` was deployed with **Microsoft Entra authentication only**, so you
> **cannot** `CREATE LOGIN … WITH PASSWORD`. The DMS migration principal must be an **Entra-based**
> login (a user, group, or service principal) created `FROM EXTERNAL PROVIDER`, and DMS connects to
> the target with **Microsoft Entra ID** authentication.

For schema migration via DMS, the migration principal on the target must be a member of the
following **server-level** roles on the target logical server (these are the exact roles called
out in the official DMS tutorial):

| Server role | Purpose |
|---|---|
| `##MS_DatabaseManager##` | Create and own databases |
| `##MS_DatabaseConnector##` | Connect to any database without a user account |
| `##MS_DefinitionReader##` | Read all catalog views (`VIEW ANY DEFINITION`) |
| `##MS_LoginManager##` | Create and delete logins |

The simplest lab option is to connect the DMS wizard with the server's **Entra admin**
(`admin@MngEnvMCAP872561.onmicrosoft.com`), which already holds full rights. For a least-privilege
principal, create a dedicated Entra-based login on `master` and grant it the four roles:

```sql
-- Run against master on sqlsrvmh2026tin4vcwzqrg3k.database.windows.net
-- Sign in as the Entra admin. NOTE: Entra-based login — no password, FROM EXTERNAL PROVIDER.
CREATE LOGIN [dms-migrator@MngEnvMCAP872561.onmicrosoft.com] FROM EXTERNAL PROVIDER;

ALTER SERVER ROLE ##MS_DefinitionReader##  ADD MEMBER [dms-migrator@MngEnvMCAP872561.onmicrosoft.com];
ALTER SERVER ROLE ##MS_DatabaseConnector## ADD MEMBER [dms-migrator@MngEnvMCAP872561.onmicrosoft.com];
ALTER SERVER ROLE ##MS_DatabaseManager##   ADD MEMBER [dms-migrator@MngEnvMCAP872561.onmicrosoft.com];
ALTER SERVER ROLE ##MS_LoginManager##      ADD MEMBER [dms-migrator@MngEnvMCAP872561.onmicrosoft.com];
```

### Tools and connectivity

- Challenge 0 complete: connectivity to `sqlvm-mh2026` is validated.
- Challenge 1 complete: the SSMS migration component + Azure Migrate assessments produced a
  remediation backlog. Apply the **Before Challenge 2** items before continuing.
- Tools on the source VM (reached over Bastion):
  - **SSMS 21+**
  - **VS Code** + MSSQL extension
  - **SqlPackage** (latest) — only if you choose the schema-first alternative in Annex D
- Network: DMS must be able to reach the SQL Server 2019 instance on TCP 1433 **through a
  self-hosted integration runtime** — required by the Azure SQL Database scenario (registered in
  Step 3.2). See
  [Self-hosted Integration Runtime](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service).

Sign in to the [Azure portal](https://portal.azure.com) with an account that has Contributor on
`rg-microhack-sql-2026` and is the Microsoft Entra admin (or a member) on the target logical server.

---

## Step 1 — Apply pre-migration remediation on the SQL 2019 source

From the Challenge 1 backlog, fix everything tagged **Before Challenge 2** on the SQL 2019
instance. Map each item back to its assessment rule:

| Backlog item | Assessment rule |
|---|---|
| Remove or rewrite cross-database queries | `CrossDatabaseReferences` |
| Disable / drop SQL Agent jobs targeting these DBs | `AgentJobs` |
| Drop linked servers referenced by these DBs | `LinkedServer` |
| Drop or refactor CLR assemblies (`UNSAFE` / `EXTERNAL_ACCESS`) | `ClrAssemblies` |
| Remove FileStream / FileTable columns | `FileStream` |
| Replace `xp_cmdshell` usage | `XpCmdshell` |
| Raise database compat level to ≥100 | `DbCompatLevelLowerThan100` |
| Disable [Change Data Capture (CDC)](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-data-capture-sql-server) on source if enabled | DMS limitation — see the tutorial |

Verify the remediation using the queries in **Annex A** at the bottom of this walkthrough.

> The DMS tutorial warns explicitly: **disable CDC on the source database before starting the
> migration**, otherwise DMS will migrate CDC-related objects and re-enabling CDC on the target
> will fail.

---

## Step 2 — Provision the target Azure SQL Database resources

### 2.1 Confirm the target logical server (already deployed, Entra-only)

The lab logical server `sqlsrvmh2026tin4vcwzqrg3k` is **already deployed empty** with **Microsoft
Entra authentication only** (no SQL admin login). You do not need to create it — just confirm it
in the portal:

1. Open **SQL servers** → `sqlsrvmh2026tin4vcwzqrg3k`.
2. Under **Settings → Microsoft Entra ID**, confirm **Microsoft Entra authentication only** is
   **enabled** and that you (or your migration principal) are set as the **Entra admin**.

### 2.2 Open the firewall for the source network

For a lab you can allow Azure services + your lab public IP. For production, use a **Private
Endpoint** instead.

1. On the logical server, open **Security → Networking**.
2. Under **Firewall rules**, select **Add your client IPv4 address**, then add a rule for the
   source/lab public IP if different.
3. Set **Allow Azure services and resources to access this server** to **Yes** (lab only), then
   **Save**.

### 2.3 Create the three empty target databases

Use the SKU from the Azure Migrate recommendation in Challenge 1. The values below are a
reasonable lab default for steady-state. **`TEAM99_SharedMasterDatabDB` uses In-Memory OLTP**, so
its target must be **Business Critical** (the only tier on Azure SQL Database that supports
memory-optimized tables); the other two map cleanly to **General Purpose**. For the migration
window itself, the official
[migration guide](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)
recommends temporarily scaling up to **Business Critical Gen5 8 vCore** (96 MB/s log generation
rate) or **Hyperscale** (100 MB/s) to avoid log-rate throttling, then scaling back down after
cut-over.

Create each database from the portal (**Create a resource → SQL Database**, or the logical
server's **+ Create database**):

| Database | Compute + storage |
|---|---|
| `TEAM99_LocalMasterDataDB` | **General Purpose** · Gen5 · 2 vCore |
| `TEAM99_TenantDataDB` | **General Purpose** · Gen5 · 2 vCore |
| `TEAM99_SharedMasterDatabDB` | **Business Critical** · Gen5 · 2 vCore (required for In-Memory OLTP) |

For each one: select the lab subscription and `rg-microhack-sql-2026`, the server
`sqlsrvmh2026tin4vcwzqrg3k`, set **Want to use SQL elastic pool? = No**, choose the service tier
above under **Compute + storage → Configure database**, leave the database **empty** (Data source =
**None**), and **Review + create**.

> Just before Step 4 you can scale the three databases up to **Business Critical Gen5 8 vCore** from
> each database's **Compute + storage** blade to avoid log-rate throttling, then scale back down
> after cut-over.

Provision the migration principal on the target server using the Entra script in the
**Prerequisites** section above before continuing.

---

## Step 3 — Create the DMS instance

### 3.1 Create the DMS instance from the portal

The `Microsoft.DataMigration` resource provider is registered automatically the first time you
create a DMS instance. Following the official tutorial:

1. In the Azure portal, navigate to **Azure Database Migration Services** and select **Create**.
2. In **Select migration scenario and Database Migration Service**, set:
   - **Source server type**: SQL Server
   - **Target server type**: Azure SQL Database
   - **Migration option**: Database Migration Service
   - Select **Create**.

   ![Select migration scenario — SQL Server to Azure SQL Database](../../Images/c2-dms-01-select-scenario.png)

3. In **Create Data Migration Service** (Basics):
   - Subscription: lab subscription
   - Resource group: `rg-microhack-sql-2026`
   - Database Migration Service name: `microhacksqlmigration`
   - Location: `France Central`
   - **Review + Create**.

   ![Create Data Migration Service — Basics](../../Images/c2-dms-02-create-basics.png)

4. After deployment, the DMS **Overview** is your hub for the migration. Note the **integration
   runtime State = not registered** — you'll register one in the next substep, because the Azure SQL
   Database scenario requires it.

   ![DMS overview — microhacksqlmigration](../../Images/c2-dms-03-overview.png)

### 3.2 Register the self-hosted integration runtime

> **Reality check (from the portal):** for the **SQL Server → Azure SQL Database** scenario the
> migration wizard is **disabled until a self-hosted integration runtime (SHIR) is connected** — even
> when the source is an Azure VM. This is a hard portal prerequisite for this target, so we register a
> SHIR here. It stays **lean and portal-driven**: download the installer, paste an auth key — **no CLI**.

1. Start a new migration (Step 4.1). In **Select new migration scenario** the portal shows a red
   warning: *"This scenario is currently disabled and requires a self-hosted integration runtime to
   access the migration source and target servers."* The prerequisites list includes **"Install, set
   up and configure Self-hosted Integration Runtime"**.

   ![New migration scenario disabled — SHIR required](../../Images/c2-dms-04-new-migration-shir-required.png)

2. Open **Configure integration runtime**. On a host that can reach the source instance (the source
   VM `sqlvm-mh2026` itself is fine for this lab):
   - **Download and install** the self-hosted integration runtime from the link on the blade.
   - Back in the portal, copy **Key 1** (or Key 2) and paste it into the Microsoft Integration Runtime
     Configuration Manager on the host to register it.
   - Wait until the runtime reports **Running / registered**.

   ![Configure integration runtime — download link and authentication keys](../../Images/c2-dms-05-configure-integration-runtime.png)

> Once the SHIR is **registered and running**, the migration scenario unlocks and the wizard in Step 4
> proceeds. Reference:
> [Tutorial: migrate SQL Server to Azure SQL Database (offline)](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service).

---

## Step 4 — Plan and start the DMS migration

DMS migrations for Azure SQL Database are launched from the **target database** blade or from
the **DMS instance** blade. The wizard is the same in both entry points.

### 4.1 Start a new migration

1. In the Azure portal, open the DMS instance `microhacksqlmigration` (or the target database
   `TEAM99_LocalMasterDataDB`) and select **New migration**.
2. In **Select new migration scenario**, set:
   - **Source server type**: SQL Server
   - **Target server type**: Azure SQL Database
   - **Migration mode**: Offline (the only supported mode)
   - Select **Select**.

The **Azure SQL Database Offline Migration Wizard** opens.

### 4.2 Source details

| Field | Value |
|---|---|
| Source SQL Server | `sqlvm-mh2026` |
| Integration runtime | The **self-hosted integration runtime** registered in Step 3.2 (State = Running) |

Select **Next: Connect to source SQL Server**.

### 4.3 Connect to source SQL Server

| Field | Value |
|---|---|
| Server name | `sqlvm-mh2026,1433` |
| Authentication | SQL Authentication |
| User name | Login with `db_owner` on each source database (for schema migration) |
| Password | (lab password) |
| Trust server certificate | Yes (lab only) |

Select **Next: Select databases for migration**.

### 4.4 Select databases for migration

Check `TEAM99_LocalMasterDataDB`, `TEAM99_SharedMasterDatabDB`, `TEAM99_TenantDataDB`. Populating
the list can take a few seconds on a small source. Select **Next: Connect to target Azure SQL
Database**.

### 4.5 Connect to target Azure SQL Database

> **Entra-only target.** The wizard's **SQL Authentication** option will fail against this server —
> it accepts Microsoft Entra principals only.

| Field | Value |
|---|---|
| Subscription / Resource group | Lab subscription / `rg-microhack-sql-2026` |
| Server | `sqlsrvmh2026tin4vcwzqrg3k` |
| Authentication | **Microsoft Entra ID — Integrated** (or *Password*) |
| User name | The Entra admin `admin@MngEnvMCAP872561.onmicrosoft.com`, or the least-privilege Entra login `dms-migrator@MngEnvMCAP872561.onmicrosoft.com` provisioned in the **Prerequisites** section |

Select **Next: Map source and target databases**.

### 4.6 Map source and target databases

Map each source database to its empty target counterpart of the same name
(`TEAM99_LocalMasterDataDB → TEAM99_LocalMasterDataDB`,
`TEAM99_SharedMasterDatabDB → TEAM99_SharedMasterDatabDB`,
`TEAM99_TenantDataDB → TEAM99_TenantDataDB`).

**Check the `Migrate Missing schema` box** for each pair. With this option DMS performs the
schema deployment as part of the migration, covering:

> Schemas, Tables, Indexes, Views, Stored Procedures, Synonyms, DDL Triggers, Defaults, Full Text
> Catalogs, Plan Guides, Roles, Rules, Application Roles, User Defined Aggregates, User Defined
> Data Types, User Defined Functions, User Defined Table Types, User Defined Types, Users
> (limited), XML Schema Collections.

Then select either **Select all tables** or filter and select per-database tables. Select
**Next: Database migration summary**.

> **Note from the DMS tutorial:** if no tables exist on the target and the **Migrate Missing
> Schema** option is not selected, the **Next** button is disabled. With the box checked, DMS
> deploys schema first, then data, even if schema migration reports object-level errors
> (except for table-object errors, which stop the run).

### 4.7 Database migration summary

Review and select **Start migration**. The wizard returns you to the Database Migration Service
dashboard.

> **Offline migration: application downtime starts now.** Coordinate with the application owner
> before clicking **Start migration**.

---

## Step 5 — Monitor the migration

1. On the DMS instance **Overview** pane, select **Monitor migrations**.
2. Use the **Migrations** tab to track in-progress, completed, and failed migrations. Use
   **Refresh** in the menu bar to update the status.

DMS reports the following statuses (per the official tutorial):

| Status | Meaning |
|---|---|
| **Creating** | DMS is starting the migration. |
| **Preparing for copy** | Disabling autostats, triggers, and indexes on target tables. |
| **Copying** | Data is being copied source → target. |
| **Copy finished** | Data copy complete; waiting on other tables to finish before final steps. |
| **Rebuilding indexes** | Rebuilding indexes on target tables. |
| **Succeeded** | All data copied and indexes rebuilt. |

3. Under **Source name**, select a database to drill into per-table status.
4. When all three migrations report **Succeeded**, proceed to Step 6.

> DMS skips tables with **0 rows** in the source — they will not appear in the per-table list
> even if you selected them in the wizard.

> **Automating at scale?** The same migration can be driven from the CLI with
> [`az datamigration`](https://learn.microsoft.com/en-us/cli/azure/datamigration) — out of scope for
> this interactive lab, but useful for repeatable, multi-database runs.

---

## Step 6 — Validate and run post-migration tasks

### 6.1 Connect from the source VM (over Bastion)

In SSMS / VS Code MSSQL extension, connect to `sqlsrvmh2026tin4vcwzqrg3k.database.windows.net`
using **Microsoft Entra ID** authentication (the server is Entra-only). Each migrated database
should be visible.

### 6.2 Compare row counts and schema

Run the validation queries in **Annex B** against both source (SQL 2019) and target (Azure SQL
DB). Row counts on the representative tables must match. Investigate any mismatch before
declaring success.

### 6.3 Smoke-test the application path

Pick the most-used stored procedure or view per database (e.g., `dbo.uspGetOpenOrders` on
`TEAM99_LocalMasterDataDB`) and execute it against the migrated database. Confirm it returns rows
and that permissions are honored.

### 6.4 Post-migration tasks (from the official migration guide)

Items from the Challenge 1 backlog marked **After Challenge 2** are now in scope. The
[migration guide](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)
recommends:

- **Update statistics** on every migrated table (DMS rebuilds indexes but doesn't refresh
  stats — see Annex F).
- Raise the target **compatibility level** when the application supports it
  (e.g. `ALTER DATABASE [TEAM99_LocalMasterDataDB] SET COMPATIBILITY_LEVEL = 160;`).
- Scale the target back down to the steady-state SKU recommended by Azure Migrate (e.g.
  General Purpose Gen5 2 vCore).
- Recreate scheduled work as **Elastic Jobs** or **Azure Automation** runbooks (SQL Agent jobs
  do not exist on Azure SQL DB).
- Recreate **logins** as Microsoft Entra ID logins where possible (Windows-auth users do not
  exist on Azure SQL DB).
- Confirm **TDE** is enabled (service-managed by default on Azure SQL DB) and document it.
- Configure **diagnostic settings** to the Log Analytics workspace `la-microhack-sql` so
  Challenge 4 (Monitoring) has data when the team starts.

### 6.5 Known DMS limitations to verify

Per the official tutorial, validate the following do not apply to your databases (and document
any that do):

- ADF-based service limits (100,000 tables/database, 10,000 concurrent database migrations/service).
- **Double-byte characters** in table names are not supported — rename before migration.
- **Reserved keywords** or **semicolons** in database names are not supported.
- **Computed columns** are not migrated by DMS.
- Source columns with default constraints that contain `NULL` are written to the target with
  the **default value**, not `NULL`. Confirm this is acceptable for the application.
- **Large blob columns** can time out. Plan a partitioned migration if you have very wide
  tables.

---

## Success criteria checklist

- [ ] Pre-migration remediation completed on the SQL 2019 source (CDC disabled if present)
- [ ] `sqlsrvmh2026tin4vcwzqrg3k` Entra-only logical server confirmed and the Entra migration
      principal (`dms-migrator@…` or the Entra admin) holds the four required server-level roles
- [ ] Three empty target databases created with the recommended SKU (`TEAM99_SharedMasterDatabDB`
      as Business Critical — In-Memory OLTP)
- [ ] `Microsoft.DataMigration` provider registered (auto with the first DMS instance)
- [ ] DMS instance `microhacksqlmigration` created via the **Select migration scenario** wizard
- [ ] DMS connectivity to the source validated through the **self-hosted integration runtime**
      (State = Running)
- [ ] DMS offline migration completed for the three databases with **Migrate Missing Schema**
      enabled; status = **Succeeded**
- [ ] Row counts match between source and target
- [ ] Smoke test executes successfully on each migrated database
- [ ] Post-migration tasks captured for follow-up challenges; statistics updated and compat
      level raised where applicable

---

## Annex A — Pre-migration remediation queries (run on SQL 2019)

```sql
-- Cross-database references (must be removed for Azure SQL DB)
SELECT DISTINCT
    referencing_object  = QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + '.' + QUOTENAME(OBJECT_NAME(d.referencing_id)),
    referenced_database = d.referenced_database_name
FROM sys.sql_expression_dependencies d
WHERE d.referenced_database_name IS NOT NULL
  AND d.referenced_database_name <> DB_NAME();

-- SQL Agent jobs that touch the source databases
USE msdb;
SELECT j.name AS job_name, s.command
FROM dbo.sysjobs j
JOIN dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE s.command LIKE '%TEAM99_LocalMasterDataDB%'
   OR s.command LIKE '%TEAM99_SharedMasterDatabDB%'
   OR s.command LIKE '%TEAM99_TenantDataDB%';

-- Linked servers
SELECT name, product, provider, data_source FROM sys.servers WHERE server_id > 0;

-- Unsupported CLR (UNSAFE / EXTERNAL_ACCESS)
SELECT name, permission_set_desc FROM sys.assemblies
WHERE is_user_defined = 1 AND permission_set_desc IN ('UNSAFE', 'EXTERNAL_ACCESS');

-- CDC enabled databases (must be disabled before DMS migration)
SELECT name, is_cdc_enabled FROM sys.databases WHERE is_cdc_enabled = 1;
```

To disable CDC on a database before migration:

```sql
USE TEAM99_LocalMasterDataDB;
EXEC sys.sp_cdc_disable_db;
```

## Annex B — Validation queries (run on both source and target)

```sql
-- Row counts per user table
SELECT
    schema_name = s.name,
    table_name  = t.name,
    row_count   = SUM(p.rows)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;

-- Object counts by type
SELECT type_desc, COUNT(*) AS object_count
FROM sys.objects
WHERE is_ms_shipped = 0
GROUP BY type_desc
ORDER BY type_desc;

-- Sample checksum on a representative table (replace [Sales].[Orders])
SELECT COUNT_BIG(*) AS row_count, CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS table_checksum
FROM [Sales].[Orders];
```

## Annex C — Troubleshooting cheatsheet

| Symptom | Likely cause | Fix |
|---|---|---|
| DMS cannot connect to the source | DMS cannot reach the source VM on TCP 1433 (NSG / firewall) | Allow inbound 1433 from the DMS service; for isolated sources register a [Self-hosted Integration Runtime](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service) |
| Wizard **Next** button greyed on schema/table step | No tables on target and `Migrate Missing Schema` not checked | Check the **Migrate Missing schema** box |
| Migration fails immediately with target login error | The Entra migration principal lacks the four server-level roles, or you chose SQL auth against the Entra-only server | Re-run the `CREATE LOGIN … FROM EXTERNAL PROVIDER` / `ALTER SERVER ROLE` script; connect with **Microsoft Entra ID** auth |
| Migration fails at **Preparing for copy** with source login error | Source login lacks `db_owner` for schema migration | Grant `db_owner` to the migration login on each source DB |
| Migration fails with **collation mismatch** | Target collation differs from source | Re-create target DB with matching collation, or set `--target-db-collation` |
| Slow migration on large table | Log-rate throttling on target | Scale target to Business Critical 8 vCore (96 MB/s) or Hyperscale for the migration window |
| `Cannot open server` from the source VM | Firewall rule missing for lab admin IP | Add SQL server firewall rule for the current IP |
| CDC re-enable fails on target after migration | CDC was left enabled on source; DMS migrated CDC objects | Disable CDC on source before migration, re-create CDC fresh on target |

## Annex D — Alternative: schema-first with SqlPackage (DACPAC)

The official DMS tutorial mentions alternative schema-migration tooling. If your team prefers a
separate schema deployment step (e.g. to gate on SqlPackage validation before running DMS),
extract a DACPAC from SQL 2019 and publish it to the empty Azure SQL DB **before** running the
DMS wizard, and **do not** check the `Migrate Missing Schema` box in Step 4.6.

```powershell
$src = "sqlvm-mh2026,1433"
$out = "C:\Lab\dacpacs"
New-Item -ItemType Directory -Path $out -Force | Out-Null

foreach ($db in @('TEAM99_LocalMasterDataDB','TEAM99_SharedMasterDatabDB','TEAM99_TenantDataDB')) {
  & SqlPackage.exe `
    /Action:Extract `
    /SourceServerName:$src /SourceDatabaseName:$db `
    /SourceUser:sa /SourcePassword:"<sql2019-sa-password>" `
    /TargetFile:"$out\$db.dacpac"
}

# Target is Entra-only — publish with Universal (interactive Entra/MFA) auth, no SQL password.
$tgt = "sqlsrvmh2026tin4vcwzqrg3k.database.windows.net"
foreach ($db in @('TEAM99_LocalMasterDataDB','TEAM99_SharedMasterDatabDB','TEAM99_TenantDataDB')) {
  & SqlPackage.exe `
    /Action:Publish `
    /SourceFile:"$out\$db.dacpac" `
    /TargetServerName:$tgt /TargetDatabaseName:$db `
    /ua:True `
    /p:BlockOnPossibleDataLoss=false /p:DropObjectsNotInSource=false
}
```

The
[SQL Database Projects extension for VS Code](https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/sql-database-projects)
is another supported alternative for repeatable schema deployments.

## Annex E — Custom Azure RBAC role for DMS migrations

From [custom-roles](https://learn.microsoft.com/en-us/data-migration/sql-server/database/custom-roles?view=azuresql).
Save as `DmsCustomRoleDemoForSqlDB.json` and create with
`az role definition create --role-definition DmsCustomRoleDemoForSqlDB.json`.

```json
{
  "properties": {
    "roleName": "DmsCustomRoleDemoForSqlDB",
    "description": "Least-privilege custom role to run DMS migrations to Azure SQL Database",
    "assignableScopes": [
      "/subscriptions/<SQLDatabaseSubscription>/resourceGroups/<SQLDatabaseResourceGroup>",
      "/subscriptions/<DatabaseMigrationServiceSubscription>/resourceGroups/<DatabaseMigrationServiceResourceGroup>"
    ],
    "permissions": [
      {
        "actions": [
          "Microsoft.Sql/servers/read",
          "Microsoft.Sql/servers/write",
          "Microsoft.Sql/servers/databases/read",
          "Microsoft.Sql/servers/databases/write",
          "Microsoft.Sql/servers/databases/delete",
          "Microsoft.DataMigration/locations/operationResults/read",
          "Microsoft.DataMigration/locations/operationStatuses/read",
          "Microsoft.DataMigration/locations/sqlMigrationServiceOperationResults/read",
          "Microsoft.DataMigration/databaseMigrations/write",
          "Microsoft.DataMigration/databaseMigrations/read",
          "Microsoft.DataMigration/databaseMigrations/delete",
          "Microsoft.DataMigration/databaseMigrations/cancel/action",
          "Microsoft.DataMigration/sqlMigrationServices/write",
          "Microsoft.DataMigration/sqlMigrationServices/delete",
          "Microsoft.DataMigration/sqlMigrationServices/read",
          "Microsoft.DataMigration/sqlMigrationServices/listAuthKeys/action",
          "Microsoft.DataMigration/sqlMigrationServices/regenerateAuthKeys/action",
          "Microsoft.DataMigration/sqlMigrationServices/deleteNode/action",
          "Microsoft.DataMigration/sqlMigrationServices/listMonitoringData/action",
          "Microsoft.DataMigration/sqlMigrationServices/listMigrations/read",
          "Microsoft.DataMigration/sqlMigrationServices/MonitoringData/read",
          "Microsoft.DataMigration/SqlMigrationServices/tasks/read",
          "Microsoft.DataMigration/SqlMigrationServices/tasks/write",
          "Microsoft.DataMigration/SqlMigrationServices/tasks/delete"
        ],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
      }
    ]
  }
}
```

Provisioning a new DMS instance still requires **Owner** or **Contributor** at the subscription
level — the custom role above only covers DMS + SQL operations within the assigned scopes.

## Annex F — Update statistics on the target after migration

```sql
-- Run on each migrated database on Azure SQL DB
DECLARE @sql nvarchar(max) = N'';
SELECT @sql = STRING_AGG(
    CONVERT(nvarchar(max),
        N'UPDATE STATISTICS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
        + N' WITH FULLSCAN;'
    ), CHAR(10))
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id;
EXEC sp_executesql @sql;
```

---

[Previous Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-03/solution-03.md)
