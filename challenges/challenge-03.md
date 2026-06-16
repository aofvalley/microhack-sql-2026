# Challenge 3 — Managed Instance Link migration (SQL Server 2025 → Azure SQL Managed Instance)

[Previous](challenge-02.md) - **[Home](../Readme.md)** - [Next Challenge](challenge-04.md)

## Goal

The goal of this exercise is to migrate a modern on-premises SQL Server 2025 database to
Azure SQL Managed Instance using the **Managed Instance link** feature, achieving near-zero
downtime by relying on a distributed availability group between the source SQL Server and the
target Managed Instance.

## Actions

* Provision (or reuse) an Azure SQL Managed Instance and validate the delegated subnet
* Configure prerequisites on the source SQL Server: TDE certificates, availability group support,
  endpoint, and required trace flags
* Create the Managed Instance link from SQL Server Management Studio
* Validate continuous replication, then perform a planned failover to cut over the workload
* Connect to the migrated database on Managed Instance and validate the application path

## Success criteria

* You established a healthy MI link between the source SQL Server and Managed Instance
* You observed replication catching up and stayed in a synchronized state
* You executed a planned failover and confirmed the database is now writable on Managed Instance
* You validated end-to-end connectivity from SQL Server Management Studio

## Learning resources

* [Managed Instance link overview](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-feature-overview?view=azuresql)
* [Prepare your environment for Managed Instance link](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-preparation?view=azuresql)
* [Failover with Managed Instance link](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-failover-database?view=azuresql)
