# Challenge 1 — Assessment

**[Home](../Readme.md)** - [Previous](challenge-00.md) - [Next Challenge](challenge-02.md)

## Goal

The goal of this exercise is to perform a complete **assessment** of the on-premises SQL Server
workloads before any migration, using Microsoft-supported tooling that replaces the retired
Azure Data Studio + Azure SQL Migration extension experience. By the end you will have a
readiness report, an SKU recommendation, and a clear remediation backlog for the source
databases.

The lab covers two source profiles:

| Source profile | Used by |
|---|---|
| Legacy **SQL Server 2012** instance with 3 application databases | Feeds Challenge 2 (DMS to Azure SQL DB) |
| Modern **SQL Server 2019/2022** instance with `AdventureWorks2019` + `WideWorldImporters` | Feeds Challenge 3 (MI Link to Azure SQL MI) |

Assess **both** profiles so that subsequent migration challenges (DMS and MI Link) start from
documented findings.

## Actions

* Run the **Microsoft Data Migration Assistant (DMA)** against the SQL Server 2012 source to get
  feature parity and compatibility findings for Azure SQL Database.
* Configure an **Azure Migrate** project, register the appliance, and discover both SQL Server
  instances.
* Create two **Azure Migrate SQL assessments**:
  * one targeting **Azure SQL Database** (sized for the 3 SQL 2012 databases)
  * one targeting **Azure SQL Managed Instance** (sized for the SQL 2019/2022 instance)
* Capture the SKU recommendation, the readiness category, and the cost estimate for each target.
* Build a remediation backlog from the assessment findings (deprecated features, breaking changes,
  unsupported objects) and decide which findings must be fixed before Challenge 2 and which can be
  fixed in-flight.

## Success criteria

* You produced a DMA report for the SQL Server 2012 source with three databases assessed against
  Azure SQL Database.
* You produced an Azure Migrate SQL assessment for the SQL Server 2012 source targeting Azure SQL
  Database, with SKU recommendation and monthly cost estimate captured.
* You produced an Azure Migrate SQL assessment for the SQL Server 2019/2022 source targeting Azure
  SQL Managed Instance, with SKU recommendation and monthly cost estimate captured.
* You documented a prioritized remediation backlog and chose which fixes happen before Challenge 2
  and which fixes happen after migration.
* You exported the assessment reports (CSV / portal share link) and stored them with the rest of
  the lab artifacts.

## Learning resources

* [Data Migration Assistant overview](https://learn.microsoft.com/en-us/sql/dma/dma-overview)
* [Azure Migrate assessment for Azure SQL](https://learn.microsoft.com/en-us/azure/migrate/concepts-azure-sql-assessment-calculation)
* [Azure Migrate appliance for SQL Server](https://learn.microsoft.com/en-us/azure/migrate/how-to-set-up-appliance-physical)
* [Compare Azure SQL deployment options](https://learn.microsoft.com/en-us/azure/azure-sql/azure-sql-iaas-vs-paas-what-is-overview)
* [Azure SQL Database feature comparison](https://learn.microsoft.com/en-us/azure/azure-sql/database/features-comparison)
