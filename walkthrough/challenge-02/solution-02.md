# Solution 2 — DMS migration: SQL Server 2012 → Azure SQL Database (2026 edition)

[Previous Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-03/solution-03.md)

## What changed since the original

The original SQL Modernization MicroHack migrated databases through the Azure Data Studio (ADS)
SQL Migration extension. ADS was retired on **28-Feb-2026**. This 2026 edition rebuilds the
migration path on top of **Azure Database Migration Service (DMS)** + **Self-hosted Integration
Runtime (SHIR)**, which is the currently supported Microsoft-native flow for SQL Server →
Azure SQL Database.

| Original lab choice | 2026 replacement | Why it changed |
|---|---|---|
| ADS + Azure SQL Migration extension | **Azure Database Migration Service** (portal, CLI, PowerShell, REST) | ADS is retired; DMS is the underlying service and remains supported. |
| Implicit runtime managed by ADS | **Self-hosted Integration Runtime** (SHIR) installed on the source network | Modern DMS uses SHIR so traffic stays inside the source network. |
| SQL Server 2019/2022 source | **SQL Server 2012** source | Matches a typical legacy modernization engagement and forces the team to confront SQL 2012 limitations. |
| Two sample databases (`AdventureWorks2019`, `WideWorldImporters`) | **Three application databases** (`app_orders`, `app_inventory`, `app_billing`) | Models a real "many small databases" portfolio migration. |
| Target Azure SQL Managed Instance | **Azure SQL Database** (single databases on one logical server) | SQL 2012 cannot use MI Link; many legacy apps map cleanly to single databases. |
| Schema and data migrated in one wizard step | Schema deployed separately with **SqlPackage** (DACPAC), data moved with DMS | Schema-first matches the supported DMS pattern for SQL → Azure SQL DB and gives a clean validation gate. |

## Lab architecture for this challenge

```
+------------------------+        SHIR/TDS         +---------------------------+
|  vm-sql-2012           |  <------------------->  |  Azure Database           |
|  (SQL Server 2012)     |                         |  Migration Service        |
|                        |                         |  (dms-microhack-2026)     |
|  app_orders            |                         +-------------+-------------+
|  app_inventory         |                                       |
|  app_billing           |                                       v
+------------------------+                         +---------------------------+
                                                   |  Azure SQL logical server |
                                                   |  sqlsrv-microhack-2026    |
                                                   |                           |
                                                   |  app_orders               |
                                                   |  app_inventory            |
                                                   |  app_billing              |
                                                   +---------------------------+
```

**Components**

- Resource group: `rg-microhack-sql-2026`
- Region: `westeurope`
- Source: `vm-sql-2012` (SQL Server 2012, three application databases)
- Target logical server: `sqlsrv-microhack-2026.database.windows.net`
- Target databases (created empty before migration): `app_orders`, `app_inventory`, `app_billing`
- DMS instance: `dms-microhack-2026` (SKU `Premium_4vCores`)
- Self-hosted Integration Runtime: `shir-microhack-2026` (installed on a Windows host in the
  source network, typically the JumpBox or a dedicated runtime VM)
- Optional staging storage account (only required for very large databases or specific online
  options): `stgmigmicrohack2026` with container `dms`

## Prerequisites

- Challenge 0 complete: connectivity to `vm-sql-2012` is validated.
- Challenge 1 complete: DMA + Azure Migrate assessments produced a remediation backlog. Apply
  the **Before Challenge 2** items before continuing.
- Permissions:
  - **Owner** or **Contributor + User Access Administrator** on the resource group.
  - **sysadmin** on the SQL Server 2012 source (read schema + data, query DMVs).
- Tools on the JumpBox / runtime host:
  - **Azure CLI 2.60+** and **Az PowerShell 11+**
  - **SSMS 20+**
  - **VS Code** + MSSQL extension
  - **SqlPackage** (latest cross-platform build) for DACPAC extract/publish
  - **Self-hosted Integration Runtime** installer (downloaded from the DMS portal blade)
- Network: the SHIR host must be able to reach the SQL Server 2012 instance on TCP 1433 and
  outbound HTTPS to Azure.

Sign in:

```bash
az login --tenant <tenant-id>
az account set --subscription "<subscription-id>"
```

---

## Step 1 — Apply pre-migration remediation on the SQL 2012 source

From the Challenge 1 backlog, fix everything tagged **Before Challenge 2** on the SQL 2012
instance. Typical items:

- Remove or rewrite **cross-database queries** (Azure SQL DB databases are isolated). Either
  consolidate the dependent tables into a single database or refactor to use **Elastic Queries**
  after migration.
- Disable / drop **SQL Server Agent jobs** that target the migrated databases. Plan the
  replacement on **Azure Automation** or **Elastic Jobs** for post-migration.
- Drop **linked servers** referenced from these databases.
- Drop or rewrite **CLR assemblies** with `EXTERNAL_ACCESS` or `UNSAFE` permission set (only
  `SAFE` CLR can move to Azure SQL DB, and even that is limited).
- Drop **FileStream** / **FileTable** columns (not supported in Azure SQL DB).
- Confirm databases use **FULL** recovery model only if you plan an online migration; otherwise
  `SIMPLE` is fine for offline.

Verify the remediation using the queries in the **Annex** at the bottom of this walkthrough.

---

## Step 2 — Provision the target Azure SQL Database resources

### 2.1 Create the logical server

```bash
az sql server create \
  --name sqlsrv-microhack-2026 \
  --resource-group rg-microhack-sql-2026 \
  --location westeurope \
  --admin-user sqladmin \
  --admin-password "<StrongLabPassword!>"
```

### 2.2 Open the firewall for the SHIR host and the JumpBox

For a lab you can allow Azure services + the lab public IP. For production, use **Private
Endpoint** instead.

```bash
az sql server firewall-rule create \
  --resource-group rg-microhack-sql-2026 \
  --server sqlsrv-microhack-2026 \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

az sql server firewall-rule create \
  --resource-group rg-microhack-sql-2026 \
  --server sqlsrv-microhack-2026 \
  --name AllowLabAdmin \
  --start-ip-address <your-public-ip> --end-ip-address <your-public-ip>
```

### 2.3 Create the three empty target databases

Use the SKU from the Azure Migrate recommendation in Challenge 1. The values below are a
reasonable lab default.

```bash
for db in app_orders app_inventory app_billing; do
  az sql db create \
    --resource-group rg-microhack-sql-2026 \
    --server sqlsrv-microhack-2026 \
    --name $db \
    --edition GeneralPurpose \
    --family Gen5 \
    --capacity 2 \
    --zone-redundant false
done
```

PowerShell equivalent:

```powershell
foreach ($db in @('app_orders','app_inventory','app_billing')) {
  New-AzSqlDatabase `
    -ResourceGroupName 'rg-microhack-sql-2026' `
    -ServerName 'sqlsrv-microhack-2026' `
    -DatabaseName $db `
    -Edition 'GeneralPurpose' `
    -ComputeGeneration 'Gen5' `
    -VCore 2 `
    -ComputeModel Provisioned
}
```

---

## Step 3 — Deploy the schema with SqlPackage (DACPAC)

DMS for Azure SQL Database migrates **data**; schema is deployed separately. For each source
database:

### 3.1 Extract a DACPAC from SQL Server 2012

Run from the JumpBox (or the SHIR host) with line-of-sight to the SQL 2012 instance:

```powershell
$src = "vm-sql-2012,1433"
$out = "C:\Lab\dacpacs"
New-Item -ItemType Directory -Path $out -Force | Out-Null

foreach ($db in @('app_orders','app_inventory','app_billing')) {
  & SqlPackage.exe `
    /Action:Extract `
    /SourceServerName:$src `
    /SourceDatabaseName:$db `
    /SourceUser:sa /SourcePassword:"<sql2012-sa-password>" `
    /TargetFile:"$out\$db.dacpac"
}
```

### 3.2 Publish the DACPAC to the empty Azure SQL Database

```powershell
$tgt = "sqlsrv-microhack-2026.database.windows.net"

foreach ($db in @('app_orders','app_inventory','app_billing')) {
  & SqlPackage.exe `
    /Action:Publish `
    /SourceFile:"C:\Lab\dacpacs\$db.dacpac" `
    /TargetServerName:$tgt `
    /TargetDatabaseName:$db `
    /TargetUser:sqladmin /TargetPassword:"<StrongLabPassword!>" `
    /p:BlockOnPossibleDataLoss=false `
    /p:DropObjectsNotInSource=false
}
```

If SqlPackage reports unsupported objects (CLR, cross-DB references, deprecated syntax), revisit
Step 1 and the Challenge 1 backlog. Do **not** continue to Step 4 until the schema publish
succeeds cleanly for all three databases.

---

## Step 4 — Provision the Azure Database Migration Service

### 4.1 Register the resource provider (one-time per subscription)

```bash
az provider register --namespace Microsoft.DataMigration --wait
```

### 4.2 Create the DMS instance (SQL migration service)

The current DMS (v2 / "SQL migration service") is the preferred shape:

```bash
az datamigration sql-service create \
  --resource-group rg-microhack-sql-2026 \
  --sql-migration-service-name dms-microhack-2026 \
  --location westeurope
```

### 4.3 Generate the SHIR authentication keys

```bash
az datamigration sql-service regenerate-auth-keys \
  --resource-group rg-microhack-sql-2026 \
  --sql-migration-service-name dms-microhack-2026 \
  --key-name authKey1
```

Copy `authKey1` — you will paste it into the SHIR configuration manager in Step 5.

---

## Step 5 — Install and register the Self-hosted Integration Runtime

1. On the SHIR host (JumpBox or `vm-runtime`), download the latest **Microsoft Integration
   Runtime** from the link shown in the DMS portal blade (or from
   https://www.microsoft.com/download/details.aspx?id=39717).
2. Run the installer and open the **Integration Runtime Configuration Manager**.
3. Paste the `authKey1` value generated in Step 4.3 and complete registration.
4. Confirm status is **Connected** in both the local manager and the DMS portal blade.
5. Open outbound firewall: TCP 443 to Azure, TCP 1433 to the SQL 2012 source.

> The same SHIR can serve all three database migrations sequentially.

---

## Step 6 — Run the DMS migrations (one project per database)

For each of the three databases, create a SQL DB migration project. The example below uses
`app_orders`; repeat for `app_inventory` and `app_billing`.

### 6.1 Portal flow (recommended for the lab)

1. In the Azure portal, open the target database `app_orders` on the logical server.
2. Select **Data management → Migrate data**.
3. Choose **Azure SQL Database** as target and **Continue**.
4. **Source SQL Server**:
   - SHIR: `dms-microhack-2026` (will be auto-discovered)
   - Source server: `vm-sql-2012,1433`
   - Authentication: SQL authentication
   - User: `sa` (or a dedicated migration login with `db_owner` on the source database)
   - Trust server certificate: **Yes** (lab only)
5. **Source database**: select `app_orders`.
6. **Target database**: `app_orders` on `sqlsrv-microhack-2026`.
7. **Login mapping**: select **Continue** for the lab (no contained-user mapping needed because
   you use SQL authentication on the target server).
8. **Migration summary**: review and **Start migration**.
9. Monitor the migration activity until status is **Succeeded**.

### 6.2 CLI flow (for automation / scripting)

```bash
# Variables
RG=rg-microhack-sql-2026
DMS=dms-microhack-2026
SRV=sqlsrv-microhack-2026
SHIR=$DMS  # SHIR is registered under the DMS instance

for DB in app_orders app_inventory app_billing; do
  az datamigration sql-db create \
    --resource-group $RG \
    --sql-db-instance-name $SRV \
    --target-db-name $DB \
    --migration-service "/subscriptions/<sub-id>/resourceGroups/$RG/providers/Microsoft.DataMigration/sqlMigrationServices/$DMS" \
    --scope "/subscriptions/<sub-id>/resourceGroups/$RG/providers/Microsoft.Sql/servers/$SRV/databases/$DB" \
    --source-database-name $DB \
    --source-sql-connection authentication=SqlAuthentication \
        data-source=vm-sql-2012,1433 \
        password='<sql2012-sa-password>' \
        user-name=sa \
        encrypt-connection=true \
        trust-server-certificate=true \
    --target-db-collation "SQL_Latin1_General_CP1_CI_AS"
done
```

Track each migration:

```bash
az datamigration sql-db show \
  --resource-group $RG \
  --sql-db-instance-name $SRV \
  --target-db-name app_orders
```

Repeat for the other two databases. Expected end state per database: `provisioningState = Succeeded`
and `migrationStatus = Succeeded`.

---

## Step 7 — Validate the migrated databases

### 7.1 Connect from the JumpBox

In SSMS / VS Code MSSQL extension, connect to `sqlsrv-microhack-2026.database.windows.net` with
the SQL admin you created. Each migrated database should be visible.

### 7.2 Compare row counts and schema

Run the validation queries in the **Annex** against both source (SQL 2012) and target (Azure SQL
DB). Row counts on the representative tables must match. Investigate any mismatch before
declaring success.

### 7.3 Smoke-test the application path

Pick the most-used stored procedure or view per database (e.g., `dbo.uspGetOpenOrders` on
`app_orders`) and execute it against the migrated database. Confirm it returns rows and that
permissions are honored.

### 7.4 Capture post-migration tasks

Items from the Challenge 1 backlog marked **After Challenge 2** are now in scope:

- Raise database **compatibility level** on target (e.g. `ALTER DATABASE app_orders SET
  COMPATIBILITY_LEVEL = 160;`).
- Recreate scheduled work as **Elastic Jobs** or **Azure Automation** runbooks.
- Add **TDE** confirmation (Azure SQL DB enables service-managed TDE by default; document it).
- Configure **diagnostic settings** to the Log Analytics workspace `la-microhack-sql` so
  Challenge 4 (Monitoring) has data when the team starts.

---

## Success criteria checklist

- [ ] Pre-migration remediation completed on the SQL 2012 source
- [ ] `sqlsrv-microhack-2026` logical server created
- [ ] Three empty target databases created with the recommended SKU
- [ ] DACPACs extracted from SQL 2012 and published to Azure SQL DB
- [ ] DMS instance `dms-microhack-2026` created
- [ ] SHIR registered and **Connected**
- [ ] Three DMS migrations report **Succeeded**
- [ ] Row counts match between source and target
- [ ] Smoke test executes successfully on each migrated database
- [ ] Post-migration tasks captured for follow-up challenges

---

## Annex A — Pre-migration remediation queries (run on SQL 2012)

```sql
-- Cross-database references (must be removed for Azure SQL DB)
SELECT DISTINCT
    referencing_object = QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + '.' + QUOTENAME(OBJECT_NAME(d.referencing_id)),
    referenced_database = d.referenced_database_name
FROM sys.sql_expression_dependencies d
WHERE d.referenced_database_name IS NOT NULL
  AND d.referenced_database_name <> DB_NAME();

-- SQL Agent jobs that touch the source databases
USE msdb;
SELECT j.name AS job_name, s.command
FROM dbo.sysjobs j
JOIN dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE s.command LIKE '%app_orders%'
   OR s.command LIKE '%app_inventory%'
   OR s.command LIKE '%app_billing%';

-- Linked servers
SELECT name, product, provider, data_source FROM sys.servers WHERE server_id > 0;

-- Unsupported CLR (UNSAFE / EXTERNAL_ACCESS)
SELECT name, permission_set_desc FROM sys.assemblies
WHERE is_user_defined = 1 AND permission_set_desc IN ('UNSAFE', 'EXTERNAL_ACCESS');
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
| DMS shows **SHIR not connected** | Outbound HTTPS blocked or wrong auth key | Re-paste `authKey1`; allow 443 outbound on SHIR host |
| Migration fails at **PreCopy** with login error | SQL 2012 login lacks `db_owner` on source DB | Grant `db_owner` to migration login on the source DB |
| Migration fails with **collation mismatch** | Target collation differs from source | Re-create target DB with matching collation, or set `--target-db-collation` |
| SqlPackage publish error: **cross-database reference** | Schema still references another DB | Remove the dependency on source, re-extract DACPAC |
| Slow migration on large table | Bandwidth between SHIR and Azure | Run SHIR on an Azure VM in `westeurope`, or scale DMS SKU |
| `Cannot open server` from JumpBox | Firewall rule missing for lab admin IP | Add SQL server firewall rule for the current IP |

---

[Previous Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-03/solution-03.md)
