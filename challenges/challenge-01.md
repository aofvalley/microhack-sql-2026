# Challenge 1 — Assessment and migration (DMS / MI Link / LRS)

**[Home](../Readme.md)** - [Next Challenge](challenge-02.md)

## Goal

The goal of this exercise is to migrate an on-premises SQL Server 2019 database to Azure SQL Managed Instance using a modern Microsoft-supported migration path.

## Actions

* Perform an assessment to reveal feature parity, compatibility, and migration blockers for Azure SQL Managed Instance
* Use Azure Migrate to analyze the workload and identify the appropriate SKU size
* Migrate the database with Azure Database Migration Service (default), Managed Instance Link, or Log Replay Service

## Success criteria

* You successfully assessed the database against Azure SQL Managed Instance
* You captured workload data and received SKU sizing guidance
* You migrated at least one database to Azure SQL Managed Instance
* You connected to the migrated database via VS Code MSSQL extension or SSMS and validated basic queries

## Learning resources

* [Azure Database Migration Service overview](https://learn.microsoft.com/en-us/azure/dms/dms-overview)
* [Managed Instance link overview](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-feature-overview?view=azuresql)
* [Migrate databases with Log Replay Service](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/log-replay-service-migrate?view=azuresql)
* [Azure Migrate assessment for Azure SQL](https://learn.microsoft.com/en-us/azure/migrate/concepts-azure-sql-assessment-calculation)
