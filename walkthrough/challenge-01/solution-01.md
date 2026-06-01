# Solution 1 — Assessment (2026 edition)

[Previous Solution](../challenge-00/solution-00.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-02/solution-02.md)

## What changed since the original

The original SQL Modernization MicroHack used **Azure Data Studio (ADS)** with the **Azure SQL
Migration extension** to assess and size in one flow. ADS was retired on **28-Feb-2026** and the
extension is deprecated, so the assessment tooling has moved into SSMS and Azure Migrate.

Per the official
[**SQL Server → Azure SQL Database migration guidance**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql#migration-tools),
Microsoft recommends **two** tools, and they do **different** jobs:

- **Azure Database Migration Service (DMS)** — the fully managed service that performs the **migration**
  with minimal downtime (Challenge 2).
- **Azure Migrate** — discovers and **assesses a SQL estate at scale**, adding a SKU recommendation and
  monthly cost. It uses a lightweight **appliance**.

**Azure Migrate is the assessment tool for this challenge.** It is the only tool that produces a
**complete** assessment: it runs the rule-mapped **readiness** check *and* returns the **SKU
recommendation + monthly cost** sizing you carry into Challenge 2. It discovers the source through a
lightweight **appliance** deployed on the source network. The SSMS migration component is kept as a
**quick readiness-only alternative** when you don't need the sizing. DMS then does the migration in
Challenge 2.

| Original lab choice | 2026 replacement | Why |
|---|---|---|
| Azure Data Studio + SQL Migration extension | **Azure Migrate** (primary assessment) **+ SSMS 21/22 migration component** (quick readiness-only alternative) | ADS retired (28-Feb-2026). Azure Migrate gives the rule-mapped readiness **and** the SKU + monthly cost sizing in one assessment; the SSMS component is a faster readiness-only check against a single instance. |
| Assessment merged with migration in one wizard | Assessment is its **own** challenge | Splitting assessment from migration mirrors real customer engagements. |
| Multi-instance fleet (SQL 2012 + SQL 2019/2022) | **Single SQL Server 2019 source** | This walkthrough runs the real lean lab: one IaaS VM → one Azure SQL Database. No Managed Instance, no fleet. |

> **Scope of this walkthrough.** Challenge 1 (assessment) and Challenge 2 (DMS migration) run
> against **one** SQL Server 2019 IaaS VM and **one** empty Azure SQL Database target. The assessment
> runs in **Azure Migrate** with a lightweight appliance and a **short** discovery window — you do
> **not** need the multi-day performance collection used in real engagements.

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
- Tools:
  - **Azure Migrate appliance** (lightweight installer) — the primary assessment path (Step 2); deploys
    on the source VM and runs discovery + the Azure SQL Database assessment.
  - **SSMS 21 / 22** with the **SQL Server hybrid and migration component** — the quick readiness-only
    alternative (Step 3); connects directly to the instance, no appliance.
- SQL Server admin rights on the source instance (the `sqladmin` Windows account is a sysadmin
  context on the VM), used to read SQL metadata.

Sign in to Azure if you want to inspect resources from CLI:

```bash
az login --tenant <tenant-id>
az account set --subscription "<subscription-id>"
```

---

## Step 1 — Connect to the source VM with Bastion

The assessment runs from the **Azure Migrate appliance** installed **on the source VM**; you reach the
VM with **Azure Bastion** (secure, browser-based RDP — no public RDP port required) to deploy the
appliance (and, if you also want the quick readiness-only check, to run SSMS there).

1. Open the VM `sqlvm-mh2026` → **Connect** → **Bastion**.
2. Confirm **Using Bastion: bastion-mh2026** shows **Provisioning State: Succeeded**.
3. Authentication type **VM Password**, enter the VM username/password, then **Connect**.

![Bastion connect blade for sqlvm-mh2026](../../Images/c1-step-04-bastion-connect.png)

> **Alternative:** if your client IP is allowed on `nsg-mh2026`, you can RDP directly with
> `mstsc /v:<vm-public-ip>`. Bastion is preferred because it needs no inbound RDP from the internet.

---

## Step 2 — Readiness assessment + SKU & cost with Azure Migrate (primary)

**Azure Migrate** is the assessment tool for this challenge. It discovers the source instance, runs the
readiness assessment against the official
[**assessment rules for SQL Server → Azure SQL Database**](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql),
and — unlike the SSMS readiness-only check — also returns the **SKU recommendation + monthly cost**
sizing you carry into Challenge 2. It relies on a lightweight **appliance** deployed on the source
network. For this single-server lab a short discovery window is enough; real engagements collect
performance data for 7–30 days for accurate right-sizing.

### 2.1 Create the Azure Migrate project and set up the appliance

1. In the portal, open **Azure Migrate** → **Get started** → **Create project**.

   ![Azure Migrate Get started landing page](../../Images/c1-step-2a-azure-migrate-get-started.png)

2. Create the project in `rg-microhack-sql-2026` (or reuse one): set the **subscription**, **resource
   group**, a **project name** (e.g. `migrate-mh2026`) and a **geography** (France).

   ![Create Azure Migrate project form](../../Images/c1-step-2b-azure-migrate-create-project.png)

   Once created, the project **Overview** is your hub for discovery, assessment and migration.

   ![Azure Migrate project overview](../../Images/c1-step-2c-azure-migrate-overview.png)

3. From the project **Overview**, click **Start discovery** and pick a discovery method. For this lab
   use **Using appliance → For Azure** (continuous discovery, ideal for detailed SQL inventory).

   ![Azure Migrate discovery methods dropdown](../../Images/c1-step-2d-azure-migrate-discovery-methods.png)

4. On the **Discover** blade, set **Are your servers virtualized?** to **Physical or other (AWS, GCP,
   Xen, etc. or if servers are Arc-enabled)**, then follow the four steps: **(1)** name the appliance
   and **generate the project key**, **(2)** download the appliance **.zip** installer.

   ![Azure Migrate Discover appliance setup form](../../Images/c1-step-2e-azure-migrate-discover-appliance.png)

5. **Generate the project key and download the appliance.** Name the appliance (e.g. `migrationsq`)
   and click **Generate key**. Wait for *"All resources have been created successfully"* and copy the
   **project key** — you'll paste it into the appliance configuration manager later. Then under
   **Download Azure Migrate appliance**, download the **.zip** (≈500 MB) installer.

   ![Azure Migrate project key generated and appliance download](../../Images/c1-step-2f-azure-migrate-project-key.png)

6. **Install the appliance on the VM (via Bastion).** Copy the .zip to `sqlvm-mh2026`, extract it,
   and you'll see the installer set — `AzureMigrateInstaller`, `AzureConnectedMachineAgent`,
   `Dra.Setup.Windows`, etc.

   ![Extracted Azure Migrate installer files](../../Images/c1-step-2g-appliance-installer-files.png)

7. **Run the installer and answer the prompts.** Open an elevated **PowerShell** (Run as
   Administrator) and run `AzureMigrateInstaller.ps1`. It validates the host (PowerShell version,
   64-bit, OS, no conflicting ASR components), then asks three questions in sequence:
   **scenario → `3` Physical or other (AWS, GCP, Xen, etc.)**, **cloud → `1` Azure Public**, and
   **connectivity → `1` default (public endpoint)**. Confirm with **`Y`** to start the deployment (it
   first removes any previously installed agents — this can take 2–3 minutes).

   ![Azure Migrate installer prompts - scenario 3 Physical, Azure Public, public endpoint](../../Images/c1-step-2h-appliance-scenario-select.png)

8. **Set up prerequisites and register the appliance.** When the installer finishes it opens the
   appliance **configuration manager** in the browser. It runs the prerequisite checks — **connectivity**,
   **time sync**, **appliance auto-update** — then **paste the project key** and click **Verify**; once
   the key is validated, click **Register** (registration can take up to 10 minutes).

   ![Azure Migrate appliance configuration manager - prerequisites and project-key registration](../../Images/c1-step-2i-appliance-prerequisites-registration.png)

9. **Add the source and discover.** Below registration, under **Manage credentials and discovery
   sources**, add the SQL connection — server `localhost`, **Windows / integrated** auth (you are
   `sqladmin`, a sysadmin context) — and trust the server certificate. Let the appliance **discover**
   the instance and start collecting. A short window (15–30 min) is enough for this lab.
   **Assessments stay disabled until discovery has populated the project.**

### 2.2 Create the Azure SQL Database assessment

1. In the Azure Migrate project, open **Assessments** → **Create assessment**.
2. Assessment type: **Azure SQL Database**.
3. Add the in-scope databases:
   - `TEAM99_LocalMasterDataDB`
   - `TEAM99_SharedMasterDatabDB`
   - `TEAM99_TenantDataDB`
   - `TEAM01_AdventureWorks2019`
4. Review the sizing criteria (performance-based vs as-on-premises) and create the assessment.

### 2.3 Capture SKU recommendation and cost

Azure Migrate returns a **recommended Azure SQL Database SKU** (service tier, vCores, storage) and a
**monthly cost estimate** for each database. Record these next to the readiness findings — you will
pick the target tier in Challenge 2 (remember In-Memory OLTP forces **Business Critical**).

> Keep the assessment export — Challenge 2 references it when you build the DMS migration project.

### 2.4 Review readiness findings

The assessment reports each database as **Ready**, **Ready with conditions**, or **Not ready**, and
maps each issue to the official rule catalogue (a **migration blocker** or a **warning**). The SSMS
readiness alternative in Step 3 shares the same rule engine, so these findings apply to both. For these
sample databases the realistic findings are:

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

---

## Step 3 — (Quick alternative) Single-instance readiness in SSMS

When you only need the **readiness** result for **one** instance and don't need the SKU + cost sizing,
**SSMS 21 / 22** ships the **SQL Server hybrid and migration component** which connects **directly** to
the instance — no appliance, no discovery window. It shares the same rule engine as Step 2, so the
readiness findings (the table in **Step 2.4**) are identical; it simply **does not** produce the Azure
Migrate **SKU + monthly cost** sizing.

### 3.1 Run the readiness assessment

1. Connect to the source instance with **SSMS 21 / 22** (over Bastion on the VM, or from your
   workstation if 1433 is reachable).
2. Right-click the instance (or use the **Migration** landing page) → **Azure Migration** → **Migrate
   SQL Server to Azure**.
3. Under **Step 1 of 4 — Migration readiness assessment**, choose **Run readiness assessment**,
   target **Azure SQL Database**, and select the in-scope databases:
   - `TEAM99_LocalMasterDataDB`
   - `TEAM99_SharedMasterDatabDB`
   - `TEAM99_TenantDataDB`
   - `TEAM01_AdventureWorks2019`
4. Use **View assessment history** to revisit prior runs. The findings map to the same rule catalogue
   reviewed in **Step 2.4**.

> The same SSMS panel also exposes an **Upgrade Assessment** ("Migrate to higher version of SQL
> Server") for in-place SQL Server version upgrades — out of scope here, but handy to know it lives in
> the same place.
> Reference:
> [Assess and upgrade with the SSMS migration component](https://techcommunity.microsoft.com/blog/microsoftdatamigration/assess-and-upgrade-to-sql-server-2025-with-ssms-migration-component/4470652).

---

## Step 4 — Review the migration target

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

## Step 5 — Build the remediation backlog

Turn the readiness findings into a prioritized backlog. Tag each row with the
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

## Step 6 — (Optional) Command-line assessment without the appliance

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

- [ ] You connected to `sqlvm-mh2026` (Bastion) and ran the **Azure Migrate** **Azure SQL Database**
      assessment for the in-scope databases, with findings mapped to official rule IDs.
- [ ] **SKU recommendation + monthly cost** captured per database from the Azure Migrate assessment.
- [ ] Tier-impacting finding (In-Memory OLTP in `TEAM99_SharedMasterDatabDB`) identified and a target
      decision recorded.
- [ ] *(Optional, single instance)* SSMS migration-component readiness assessment run as a quick
      cross-check of the same findings.
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
