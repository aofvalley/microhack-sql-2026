# Challenge 2 — DMS migration (SQL Server 2012 → Azure SQL Database)

[Previous](challenge-01.md) - **[Home](../Readme.md)** - [Next Challenge](challenge-03.md)

## Goal

The goal of this exercise is to migrate **three application databases** running on an
on-premises **SQL Server 2012** instance to **Azure SQL Database** using **Azure Database
Migration Service (DMS)**. This is the modern Microsoft-supported replacement for the retired
Azure Data Studio + Azure SQL Migration extension workflow.

You will use the assessment findings produced in Challenge 1 to decide which databases need
schema fixes before migration, then run an offline (or online, where the source supports it)
DMS migration to land each database as a standalone Azure SQL Database on a shared logical
server.

## Source and target

| Item | Value |
|---|---|
| Source server | SQL Server 2012 (`vm-sql-2012`) |
| Source databases | `app_orders`, `app_inventory`, `app_billing` (use the actual names from Challenge 0) |
| Target service | Azure SQL Database (single databases, **not** Managed Instance) |
| Target logical server | `sqlsrv-microhack-2026` |
| Target SKU baseline | General Purpose, Gen5, 2–4 vCore per DB (use the Azure Migrate recommendation from Challenge 1) |
| Migration service | Azure Database Migration Service (DMS) |
| Migration runtime | Self-hosted Integration Runtime (SHIR) on the source network |

> SQL Server 2012 is out of Extended Support. DMS supports it as a migration source for Azure
> SQL Database, but you cannot use Managed Instance Link from a 2012 source — that is why the
> 2012 fleet goes through DMS to Azure SQL DB in this lab, while the 2019/2022 fleet uses MI
> Link in Challenge 3.

## Actions

* Apply pre-migration remediation from the Challenge 1 backlog (e.g. remove cross-DB queries,
  externalize SQL Agent jobs, drop unsupported objects) on the SQL 2012 source.
* Provision the target Azure SQL Database **logical server** and three empty target databases
  sized per the Azure Migrate recommendation.
* Provision the **Azure Database Migration Service** instance and configure a **Self-hosted
  Integration Runtime** on the source network so DMS can reach the SQL 2012 instance.
* For each of the three source databases, deploy the schema (SqlPackage / DACPAC or scripted)
  and run a DMS migration project to move the data.
* Validate connectivity, row counts, and a smoke-test query against each migrated Azure SQL
  Database from the JumpBox.

## Success criteria

* The three databases are migrated to Azure SQL Database and visible on the target logical
  server `sqlsrv-microhack-2026`.
* DMS reports a **Succeeded** status for each migration activity.
* Row counts on the target match the source for a representative table per database (use the
  `Annex — Validation queries` from the walkthrough).
* You can connect to each target database from VS Code MSSQL extension and SSMS and run a
  simple `SELECT` against a user table.
* Pre-migration blockers from the Challenge 1 backlog are resolved or documented as accepted
  post-migration work items.

## Learning resources

* [Azure Database Migration Service overview](https://learn.microsoft.com/en-us/azure/dms/dms-overview)
* [Migrate SQL Server to Azure SQL Database using DMS](https://learn.microsoft.com/en-us/azure/dms/tutorial-sql-server-to-azure-sql)
* [Self-hosted Integration Runtime in DMS (SQL → Azure SQL DB)](https://learn.microsoft.com/en-us/azure/dms/migration-using-azure-data-studio)
* [Azure SQL Database vCore-based purchasing model](https://learn.microsoft.com/en-us/azure/azure-sql/database/service-tiers-vcore)
* [SqlPackage extract / publish for schema deployment](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage)
* [SQL Server 2012 end-of-support and migration options](https://learn.microsoft.com/en-us/lifecycle/products/sql-server-2012)
