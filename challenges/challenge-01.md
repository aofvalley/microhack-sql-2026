# Challenge 1 — Assessment

**[Home](../Readme.md)** - [Previous](challenge-00.md) - [Next Challenge](challenge-02.md)

## Goal

The goal of this exercise is to perform a complete **assessment** of the on-premises SQL Server
workload against the **official Microsoft assessment rules**
([reference](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql)),
before any migration. You assess the source against **every** Azure SQL target — **Azure SQL
Database**, **Azure SQL Managed Instance**, and **SQL Server on Azure VM (IaaS)** — so the same
assessment drives whichever migration path you later choose. By the end you will have, per target,
a readiness report, the recommended deployment target, an SKU recommendation with monthly cost,
and a clear remediation backlog driven by the named assessment rules.

This challenge replaces the retired Azure Data Studio + Azure SQL Migration extension flow with
the two Microsoft-supported assessment tools: **Azure Migrate** (primary — it evaluates the source
against **all three** Azure SQL targets, returning the rule-mapped readiness check, the
**recommended deployment target**, the SKU recommendation, and the monthly cost via a lightweight
appliance) and the **SSMS migration component** (a quick readiness-only alternative). See the
[migration overview](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql)
for the supported tooling matrix.

The lab uses a single source instance, assessed against the full set of Azure SQL targets:

| Source | Targets evaluated | Feeds |
|---|---|---|
| The **SQL Server 2019** IaaS VM `<prefix>u<NN>-srcvm19` (e.g. `mhu01-srcvm19`) with the restored sample databases **AdventureWorks2019** and **WideWorldImporters** | Azure SQL Database · Azure SQL Managed Instance · SQL Server on Azure VM (IaaS) | Challenge 2 (DMS → Azure SQL Database) and Challenge 3 (MI Link → Azure SQL Managed Instance) |

Assess this instance against every target so each subsequent migration challenge — and any IaaS
rehost decision — starts from the same documented findings.

> **Your environment.** All names use the `<prefix>u<NN>` convention from
> [Challenge 0](challenge-00.md), where `<NN>` is your two-digit user number (e.g. `mhu01`). The
> resources you use in this challenge are pre-provisioned in your resource group `rg-mh-user<NN>`:
>
> | Resource | Name | Role in this challenge |
> | --- | --- | --- |
> | Source VM (SQL Server 2019) | `<prefix>u<NN>-srcvm19` (e.g. `mhu01-srcvm19`) | The source instance you assess. Connect through Azure Bastion `<prefix>u<NN>-bastion`. |
> | Source VM (SQL Server 2025) | `<prefix>u<NN>-srcvm25` (e.g. `mhu01-srcvm25`) | Not used here — it is the MI Link source for Challenge 3. |
> | Azure Migrate project | `<prefix>u<NN>-migrate` (e.g. `mhu01-migrate`) | Pre-created Azure Migrate project. Register the appliance and run the assessments here. |
> | Azure SQL logical server | `<prefix>u<NN>-sqlsrv-…` (e.g. `mhu01-sqlsrv-…`) | The DMS target used in Challenge 2; not assessed here. |

## Actions

* Connect to the source VM `<prefix>u<NN>-srcvm19` (e.g. `mhu01-srcvm19`) with **Azure Bastion**
  (`<prefix>u<NN>-bastion`) and deploy the **Azure Migrate appliance** on the SQL Server 2019
  instance.
* Use the pre-provisioned **Azure Migrate** project `<prefix>u<NN>-migrate` (e.g. `mhu01-migrate`)
  in your resource group `rg-mh-user<NN>`, discover the instance, and run a short discovery window
  (real engagements collect performance data for 7–30 days; this single-server lab needs only a
  short window).
* Create **three Azure Migrate SQL assessments** from the same discovery data, one per target —
  **Azure SQL Database**, **Azure SQL Managed Instance**, and **SQL Server on Azure VM (IaaS)** —
  and capture, per target, the readiness category, the recommended SKU/size, and the monthly cost.
* Compare the three targets and record the **recommended deployment target** Azure Migrate
  surfaces, plus the trade-offs (managed-PaaS feature parity vs lift-and-shift on IaaS).
* Optionally run the **SSMS migration component** readiness-only check against the instance when
  you need a fast readiness signal without the sizing.
* Build a remediation backlog using the **official assessment-rule names** (e.g. `AgentJobs`,
  `CrossDatabaseReferences`, `LinkedServer`, `XpCmdshell`, `DbCompatLevelLowerThan100`), noting
  which rules block **Azure SQL Database** specifically but are non-issues for Managed Instance or
  IaaS, and decide which fixes happen before Challenge 2 and which can be deferred.

## Success criteria

* You produced an **Azure Migrate** SQL assessment for the SQL Server 2019 source targeting
  **Azure SQL Database**, with readiness category, SKU recommendation, and monthly cost captured.
  Findings are mapped to the official rule IDs.
* You produced an **Azure Migrate** SQL assessment for the same source targeting **Azure SQL
  Managed Instance**, with readiness, SKU recommendation, and monthly cost captured.
* You produced an **Azure Migrate** SQL assessment for the same source targeting **SQL Server on
  Azure VM (IaaS)**, with the recommended VM size and monthly cost captured.
* You compared the three targets, recorded the recommended deployment target, and documented a
  prioritized remediation backlog using the official assessment-rule names — flagging which
  findings are Azure SQL Database-only blockers.
* You exported the assessment reports and stored them with the rest of the lab artifacts.

## Learning resources

* [Migration overview: SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/overview?view=azuresql)
* [Migration guide: SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/guide?view=azuresql)
* [Assessment rules for SQL Server to Azure SQL Database](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql)
* [Azure Migrate assessment for Azure SQL](https://learn.microsoft.com/en-us/azure/migrate/concepts-azure-sql-assessment-calculation)
* [Compare Azure SQL deployment options (Database, Managed Instance, SQL on VM)](https://learn.microsoft.com/en-us/azure/azure-sql/azure-sql-iaas-vs-paas-what-is-overview)
* [Azure SQL Database feature comparison](https://learn.microsoft.com/en-us/azure/azure-sql/database/features-comparison)
* [Azure SQL Managed Instance overview](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/sql-managed-instance-paas-overview)
