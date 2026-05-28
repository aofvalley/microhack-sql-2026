# Challenge 2 — DMS migration (SQL Server 2012 → Azure SQL Database)

[Previous](challenge-01.md) - **[Home](../Readme.md)** - [Next Challenge](challenge-03.md)

## Goal

The goal of this exercise is to migrate **three application databases** running on an
on-premises **SQL Server 2012** instance to **Azure SQL Database** using **Azure Database
Migration Service (DMS)** following the official
[SQL Server → Azure SQL Database DMS tutorial](https://learn.microsoft.com/en-us/data-migration/sql-server/database/database-migration-service?view=azuresql).

You will use the assessment findings produced in Challenge 1 to decide which databases need
schema fixes before migration, then run an **offline** DMS migration (the only mode supported
for Azure SQL Database targets) to land each database as a standalone Azure SQL Database on a
shared logical server. DMS itself deploys the schema as part of the migration (the
**Migrate Missing Schema** option of the wizard), so you do not need a separate DACPAC step
for the happy path.

## Source and target

| Item | Value |
|---|---|
| Source server | SQL Server 2012 (`vm-sql-2012`) |
| Source databases | `app_orders`, `app_inventory`, `app_billing` (use the actual names from Challenge 0) |
| Target service | Azure SQL Database (single databases, **not** Managed Instance) |
| Target logical server | `sqlsrv-microhack-2026` |
| Target SKU baseline | General Purpose Gen5, 2–4 vCore per DB (use the Azure Migrate recommendation from Challenge 1). Scale up to Business Critical Gen5 8 vCore during migration if log throttling becomes the bottleneck (see the [migration guide](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)). |
| Migration service | Azure Database Migration Service (offline mode) |
| Migration runtime | Self-hosted Integration Runtime (SHIR) **v5.37+** on the source network |
| Migration mode | **Offline only** — online migration is not available for Azure SQL Database targets |

> SQL Server 2012 is out of Extended Support. DMS supports it as a migration source for Azure
> SQL Database (sources from SQL Server 2008 onward are supported), but you cannot use Managed
> Instance Link from a 2012 source — that is why the 2012 fleet goes through DMS to Azure SQL
> DB in this lab, while the 2019/2022 fleet uses MI Link in Challenge 3.

## Actions

* Apply pre-migration remediation from the Challenge 1 backlog (e.g. remove cross-database
  queries, externalize SQL Agent jobs, drop unsupported objects) on the SQL 2012 source.
* Provision the target Azure SQL Database **logical server** and three empty target databases
  sized per the Azure Migrate recommendation.
* Register the **Microsoft.DataMigration** resource provider and assign the required RBAC roles
  (built-in roles, or the custom DMS role described in the
  [custom roles documentation](https://learn.microsoft.com/en-us/data-migration/sql-server/database/custom-roles?view=azuresql)).
* Provision the **Azure Database Migration Service** instance and configure a **Self-hosted
  Integration Runtime** (SHIR v5.37+) on the source network so DMS can reach the SQL 2012
  instance.
* Create the migration login on each target database, granting the four required server-level
  roles (`##MS_DatabaseManager##`, `##MS_DatabaseConnector##`, `##MS_DefinitionReader##`,
  `##MS_LoginManager##`).
* For each of the three source databases, run an **offline** DMS migration with **Migrate
  Missing Schema** enabled so DMS deploys both the schema and the data.
* Validate connectivity, row counts, and a smoke-test query against each migrated Azure SQL
  Database from the JumpBox, then run the post-migration tasks (update statistics, raise
  compatibility level).

## Success criteria

* The three databases are migrated to Azure SQL Database and visible on the target logical
  server `sqlsrv-microhack-2026`.
* DMS reports a **Succeeded** status for each migration in the **Monitor migrations** view.
* Row counts on the target match the source for a representative table per database (use the
  `Annex — Validation queries` from the walkthrough).
* You can connect to each target database from VS Code MSSQL extension and SSMS and run a
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
* [SQL Server 2012 end-of-support and migration options](https://learn.microsoft.com/en-us/lifecycle/products/sql-server-2012)
