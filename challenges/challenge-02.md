# Challenge 2 — DMS migration (SQL Server 2019 → Azure SQL Database)

[Previous](challenge-01.md) - **[Home](../Readme.md)** - [Next Challenge](challenge-03.md)

## Goal

The goal of this exercise is to migrate a **single application database** running on the
on-premises **SQL Server 2019** instance from Challenge 1 to **Azure SQL Database** using
**Azure Database Migration Service (DMS)** following the official
[SQL Server → Azure SQL Database DMS tutorial](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service?view=azuresql).

You will use the assessment findings produced in Challenge 1 to apply any schema fixes before
migration, then run an **offline** DMS migration (the only mode supported for Azure SQL Database
targets) to land the database as a standalone Azure SQL Database on a logical server. DMS itself
deploys the schema as part of the migration (the **Migrate Missing Schema** option of the
wizard), so you do not need a separate DACPAC step for the happy path. The same steps repeat per
database when migrating more than one at scale.

## Source and target

| Item | Value |
|---|---|
| Source server | SQL Server 2019 on `<prefix>u<NN>-srcvm19` (e.g. `mhu01-srcvm19`), the Challenge 1 VM |
| Source database | **AdventureWorks2019** — a single application database restored on the source instance (the other available database, **WideWorldImporters**, is reserved for the Challenge 3 MI Link path) |
| Target service | Azure SQL Database (single database, **not** Managed Instance) |
| Target logical server | `<prefix>u<NN>-sqlsrv-…` (e.g. `mhu01-sqlsrv-…`, **SQL authentication**) |
| Target SKU baseline | General Purpose Gen5, 2–4 vCore (use the Azure Migrate recommendation from Challenge 1). Scale up to Business Critical Gen5 8 vCore during migration if log throttling becomes the bottleneck (see the [migration guide](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)). |
| Migration service | Azure Database Migration Service (offline mode) |
| Migration runtime | Self-hosted Integration Runtime (SHIR) **v5.37+** on the source network (the same VM that hosts the source instance, `<prefix>u<NN>-srcvm19`) |
| Migration mode | **Offline only** — online migration is not available for Azure SQL Database targets |

> **Target authentication and prerequisites.** The Azure SQL Database target uses **SQL
> authentication** (a SQL login on the logical server), not Entra-only auth. DMS does **not**
> create the target database — pre-create an **empty** `AdventureWorks2019` sized per the Azure Migrate
> recommendation before you start the wizard, and open the Azure SQL **server firewall** so the
> SHIR/source network can reach it. The Managed Instance Link path is covered in Challenge 3.

## Actions

* Apply pre-migration remediation from the Challenge 1 backlog (e.g. remove cross-database
  queries, externalize SQL Agent jobs, drop unsupported objects) on the SQL Server 2019 source.
* Pre-create the **empty** target Azure SQL Database `AdventureWorks2019` on the existing logical server
  `<prefix>u<NN>-sqlsrv-…` (e.g. `mhu01-sqlsrv-…`), sized per the Azure Migrate recommendation, and
  open the Azure SQL **server firewall** so the source network can reach it.
* Register the **Microsoft.DataMigration** resource provider and assign the required RBAC roles
  (built-in roles, or the custom DMS role described in the
  [custom roles documentation](https://learn.microsoft.com/en-us/data-migration/sql-server/database/custom-roles?view=azuresql)).
* Provision the **Azure Database Migration Service** instance and configure a **Self-hosted
  Integration Runtime** (SHIR v5.37+) on the source network (the source VM `<prefix>u<NN>-srcvm19`)
  so DMS can reach the SQL Server 2019 instance.
* Create the source SQL login DMS uses to read the instance, and a target migration login on the
  logical server granting the four required server-level roles (`##MS_DatabaseManager##`,
  `##MS_DatabaseConnector##`, `##MS_DefinitionReader##`, `##MS_LoginManager##`).
* Run an **offline** DMS migration with **Migrate Missing Schema** enabled so DMS deploys both the
  schema and the data for `AdventureWorks2019`.
* Validate connectivity, row counts, and a smoke-test query against the migrated Azure SQL
  Database, then run the post-migration tasks (update statistics, raise compatibility level).

## Success criteria

* The database is migrated to Azure SQL Database and visible on the target logical server
  `<prefix>u<NN>-sqlsrv-…` (e.g. `mhu01-sqlsrv-…`).
* DMS reports a **Succeeded** status for the migration in the **Monitor migrations** view.
* Row counts on the target match the source for a representative table (use the
  `Annex — Validation queries` from the walkthrough).
* You can connect to the target database from VS Code MSSQL extension and SSMS and run a
  simple `SELECT` against a user table.
* Pre-migration blockers from the Challenge 1 backlog are resolved or documented as accepted
  post-migration work items.

## Learning resources

* [Migration overview: SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql)
* [Migration guide: SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)
* [Tutorial: Migrate SQL Server to Azure SQL Database (offline) with DMS](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service?view=azuresql)
* [Custom roles for SQL Server → Azure SQL Database migrations](https://learn.microsoft.com/en-us/data-migration/sql-server/database/custom-roles?view=azuresql)
* [Self-hosted integration runtime for database migrations](https://learn.microsoft.com/en-us/azure/dms/self-hosted-integration-runtime)
* [Azure SQL Database vCore-based purchasing model](https://learn.microsoft.com/en-us/azure/azure-sql/database/service-tiers-vcore)
