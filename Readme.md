![hero](./Images/SQLMicroHack-2026.jpg)

# MicroHack — SQL Modernization (2026 edition)

- [**MicroHack introduction**](#microhack-introduction)
- [**MicroHack context**](#microhack-context)
- [**Objectives**](#objectives)
- [**MicroHack Challenges**](#microhack-challenges)
- [**Contributors**](#contributors)
- [**Original microhack & attribution**](#original-microhack--attribution)
- [**License**](#license)

# MicroHack introduction

This MicroHack walks through SQL Server modernization with a focus on current Microsoft-supported assessment and migration paths for Azure SQL Managed Instance.

**What changed since the original:** Azure Data Studio was retired on 28-Feb-2026 and the Azure SQL Migration extension was deprecated. This edition replaces that flow with Azure Database Migration Service (DMS), Managed Instance Link, and Log Replay Service (LRS). Sample databases changed from internal `TEAMxx_*` databases to public AdventureWorks2019 and WideWorldImporters. Source SQL Server versions move from 2012/2016 to 2019/2022. The original Microsoft MicroHack is credited here: https://github.com/microsoft/MicroHack/tree/main/03-Azure/01-02%20Data/02-SQL_Modernization

# MicroHack context

This scenario modernizes SQL Server workloads to Azure and highlights cost optimization, flexibility, scalability, improved security and compliance, and simplified management and monitoring.

# Objectives

After completing this MicroHack you will be able to:

* Implement a proof-of-concept (PoC) for migrating an on-premises SQL Server 2019 or SQL Server 2022 database into Azure SQL Managed Instance (SQL MI)
* Perform assessments to reveal feature parity, compatibility, and modernization issues between the on-premises SQL Server database and Azure SQL targets
* Migrate on-premises databases into Azure using currently supported Microsoft migration services
* Enable advanced SQL MI features to improve security, monitoring, and performance in your customer's application
* Understand how to implement a cloud migration solution for business-critical applications and databases

# MicroHack challenges

## General prerequisites

This MicroHack has a few but important prerequisites:

* Basic Azure knowledge [(Azure fundamentals)](https://learn.microsoft.com/en-us/training/paths/azure-fundamentals-describe-azure-architecture-services/)
* Basic database knowledge
* Microsoft Teams Desktop Sharing should be allowed to collaborate with other participants (only for remote deliveries)
* Az CLI 2.60+
* Az PowerShell 11+
* SSMS 20+
* VS Code with the MSSQL extension (replacement for Azure Data Studio)

## Quick deploy

To run the lab against your own Azure subscription, see
[`scripts/RUN-ME.md`](./scripts/RUN-ME.md) for the 5-minute single-user path
or [`scripts/README.md`](./scripts/README.md) for the full multi-team
configuration reference.

## Challenges

* [Challenge 1 — Assessment and migration](challenges/challenge-01.md) **<- Start here**
* [Challenge 2 — Monitoring and Performance on Azure SQL Managed Instance](challenges/challenge-02.md)
* [Challenge 3 — Security on Azure SQL Managed Instance](challenges/challenge-03.md)

## Solutions - Spoilerwarning

* [Solution 1](./walkthrough/challenge-01/solution-01.md)
* [Solution 2](./walkthrough/challenge-02/solution-02.md)
* [Solution 3](./walkthrough/challenge-03/solution-03.md)

## Contributors

* Alfonso Del Valle — Microsoft CSA Data & AI ([LinkedIn](https://www.linkedin.com/in/alfonsodelvalle/))

## Original microhack & attribution

This lab is a derivative of the Microsoft MicroHack SQL Modernization lab. Original contributors:

* Cornel Sukalla ([LinkedIn](https://www.linkedin.com/in/cornelsukalla/))
* Mert Següner ([LinkedIn](https://www.linkedin.com/in/mertsenguner/))
* Sean Cowburn ([LinkedIn](https://www.linkedin.com/in/sean-cowburn/))

## License

This is a derivative work licensed under MIT. The original is available in the Microsoft MicroHack repository: https://github.com/microsoft/MicroHack/tree/main/03-Azure/01-02%20Data/02-SQL_Modernization
