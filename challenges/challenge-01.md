# Challenge 1 — Assessment

**[Home](../Readme.md)** - [Previous](challenge-00.md) - [Next Challenge](challenge-02.md)

## Goal

The goal of this exercise is to perform a complete **assessment** of the on-premises SQL Server
workloads against the **official Microsoft assessment rules** for Azure SQL Database
([reference](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql)),
before any migration. By the end you will have, for each source profile, a readiness report, an
SKU recommendation, and a clear remediation backlog driven by the named assessment rules.

This challenge replaces the retired Azure Data Studio + Azure SQL Migration extension flow with
the two Microsoft-supported assessment tools: **Data Migration Assistant (DMA)** and
**Azure Migrate** (see the
[migration overview](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql)
for the supported tooling matrix).

The lab covers two source profiles:

| Source profile | Used by |
|---|---|
| Legacy **SQL Server 2012** instance with 3 application databases | Feeds Challenge 2 (DMS to Azure SQL Database) |
| Modern **SQL Server 2019/2022** instance with `AdventureWorks2019` + `WideWorldImporters` | Feeds Challenge 3 (MI Link to Azure SQL Managed Instance) |

Assess **both** profiles so that subsequent migration challenges start from documented findings.

## Actions

* Run the **Microsoft Data Migration Assistant (DMA)** against the SQL Server 2012 source to get
  the official assessment-rule findings against Azure SQL Database.
* Configure an **Azure Migrate** project and the **Azure Migrate appliance** to discover and
  performance-collect both SQL Server instances.
* Create two **Azure Migrate SQL assessments**:
  * one targeting **Azure SQL Database** (sized for the 3 SQL 2012 databases)
  * one targeting **Azure SQL Managed Instance** (sized for the SQL 2019/2022 instance)
* Capture, per assessment, the SKU recommendation, the readiness category, and the monthly cost
  estimate.
* Build a remediation backlog using the **official assessment-rule names** (e.g. `AgentJobs`,
  `CrossDatabaseReferences`, `LinkedServer`, `XpCmdshell`, `DbCompatLevelLowerThan100`) and
  decide which findings must be fixed before Challenge 2 and which can be fixed in-flight or
  post-migration.

## Success criteria

* You produced a DMA report for the SQL Server 2012 source with the three databases assessed
  against Azure SQL Database. Findings are mapped to the official rule IDs.
* You produced an Azure Migrate SQL assessment for the SQL Server 2012 source targeting Azure
  SQL Database, with SKU recommendation and monthly cost estimate captured.
* You produced an Azure Migrate SQL assessment for the SQL Server 2019/2022 source targeting
  Azure SQL Managed Instance, with SKU recommendation and monthly cost estimate captured.
* You documented a prioritized remediation backlog using the official assessment-rule names and
  chose which fixes happen before Challenge 2 and which fixes happen after migration.
* You exported the assessment reports and stored them with the rest of the lab artifacts.

## Learning resources

* [Migration overview: SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql)
* [Migration guide: SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)
* [Assessment rules for SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql)
* [Data Migration Assistant overview](https://learn.microsoft.com/en-us/sql/dma/dma-overview)
* [Azure Migrate assessment for Azure SQL](https://learn.microsoft.com/en-us/azure/migrate/concepts-azure-sql-assessment-calculation)
* [Compare Azure SQL deployment options](https://learn.microsoft.com/en-us/azure/azure-sql/azure-sql-iaas-vs-paas-what-is-overview)
* [Azure SQL Database feature comparison](https://learn.microsoft.com/en-us/azure/azure-sql/database/features-comparison)
