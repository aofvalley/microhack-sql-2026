# Challenge 0 — SQL Server access setup

**[Home](../Readme.md)** - [Next Challenge](challenge-01.md)

> **Owner:** _to be assigned_ — this challenge is a placeholder for the team member working on
> source environment access. Replace this stub with the final content on your own branch.

## Goal

The goal of this exercise is to ensure every attendee can reach the lab source environment
(the **SQL Server 2019** instance used across Challenges 1–5), authenticate against the instance,
and validate basic connectivity from the workstation and from the JumpBox.

## Actions

* Deploy or connect to the lab JumpBox over Azure Bastion
* Validate Azure CLI / Az PowerShell sign-in against the lab tenant and subscription
* Connect to the source SQL Server instance with SSMS 20+ and the VS Code MSSQL extension
* Verify network paths (NSG rules, private endpoints) needed by later challenges
* Confirm the sample databases are online on the source instance

## Success criteria

* You connected to the **SQL Server 2019** instance and listed the restored sample databases
  (AdventureWorks2019 / WideWorldImporters / AdventureWorksDW2019) used in the migration challenges
* You can run a simple `SELECT @@VERSION` from SSMS and from VS Code against the instance
* You captured the connection strings and credentials in your secure notes for the rest of the
  MicroHack

## Learning resources

* [Connect to a SQL Server instance using SSMS](https://learn.microsoft.com/en-us/sql/ssms/quickstarts/ssms-connect-query-sql-server)
* [VS Code MSSQL extension](https://learn.microsoft.com/en-us/sql/tools/visual-studio-code/sql-server-develop-use-vscode)
* [Azure Bastion overview](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview)
