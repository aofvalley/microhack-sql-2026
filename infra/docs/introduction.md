# Introduction for students — MicroHack SQL 2026

**[Home](../README.md)** - [Architecture](architecture.md) - [Access guide (Challenge 0)](access-guide.md)

Welcome to the SQL Server modernization MicroHack! In this lab you will **assess** a SQL
Server 2019 instance, **migrate it to Azure SQL Database** with Azure Database Migration
Service (DMS), and **migrate a SQL Server 2025 instance to Azure SQL Managed Instance** with
Managed Instance Link.

Before you start the challenges, read this introduction and complete the
[access checklist](#access-checklist). If something does not work, tell a facilitator
**before** you begin.

## Your environment

Each student gets a fully **isolated, personal** environment: one resource group
(`rg-<prefix>-user<NN>`, for example `rg-mhlab-user01`) containing everything you need. You do
not share resources with the rest of the class.

![Per-student architecture for user01](images/architecture.png)

### Components and what they are for

| Component | What it is | You will use it to |
| --- | --- | --- |
| **Entra ID user** | Your access identity (`<prefix>user<NN>@<tenant>`, e.g. `mhlabuser01@…`) | Sign in to the Azure portal and to the VM. |
| **Resource group** | `rg-<prefix>-user<NN>` (e.g. `rg-mhlab-user01`) | Contains all your resources; only you can access it. |
| **Source VM 1 (SQL 2019)** | Windows Server 2022 + SQL Server 2019 Developer (`mhlabu01-srcvm19`) | The **source** for the DMS migration (Challenge 2). Ships with SSMS, Azure CLI and VS Code. |
| **Source VM 2 (SQL 2025)** | Windows Server 2025 + SQL Server 2025 Enterprise Dev (`mhlabu01-srcvm25`) | The **source** for the MI Link migration (Challenge 3). Same DBs and tools as VM 1. |
| **Azure Bastion** | Browser-based RDP, no public RDP client needed (`mhlabu01-bastion`) | Connect to both source VM desktops securely. |
| **Azure SQL server** | PaaS logical server with a public endpoint (`mhlabu01-sqlsrv-…`) | **Target** of the DMS migration (Challenge 2). You create the target database. |
| **Azure SQL Managed Instance** | Managed PaaS instance (`mhlabu01-sqlmi-…`) | **Target** of the MI Link migration (Challenge 3). |
| **Key Vault** | Per-student vault (`mhlabu01kv…`) | Holds your lab credentials; you read them with your Key Vault Secrets User role. |
| **Log Analytics workspace** | Per-student workspace (`mhlabu01-law`) | Collects diagnostics/telemetry for your lab resources. |

> Networking is **public by design** to keep the lab simple. There are no private endpoints or
> peering to configure.

### Sample databases

Both source VMs already have two databases restored and **online**:

- **AdventureWorks2019**
- **WideWorldImporters**

These are your source workload for the assessment and the migrations.

## Your challenges (overview)

| Challenge | What you will do | Primary resource |
| --- | --- | --- |
| 0 — Access and orientation | Verify your access (this checklist) | User, portal, Bastion, VM |
| 1 — Assess the source | Analyze SQL Server 2019 with SSMS | Source VM (SQL 2019) |
| 2 — Migrate to Azure SQL DB | Migration with DMS | Source VM (SQL 2019) + Azure SQL server |
| 3 — Migrate to Azure SQL MI | Migration with MI Link | Source VM (SQL 2025) + Azure SQL Managed Instance |
| 4 — Validate and modernize | Compare source and targets | All |
| 5 — Cleanup and review | Final review | (facilitator) |

## Access checklist

Complete these at the start (Challenge 0). The **step-by-step guide** is in
[`access-guide.md`](access-guide.md).

- [ ] **1. User** — the facilitator gives you your user `<prefix>user<NN>@<tenant>` (e.g.
      `mhlabuser01@<your-tenant>.onmicrosoft.com`) and a password. Change it on first
      sign-in if prompted.
- [ ] **2. Azure portal** — you sign in at <https://portal.azure.com> and **see your resource
      group** `rg-mhlab-user01` (and only yours).
- [ ] **3. Source VMs via Bastion** — you open the VMs `mhlabu01-srcvm19` and `mhlabu01-srcvm25`
      → **Connect → Bastion** and reach the Windows desktop of each.
- [ ] **4. Source SQL** — inside a VM, you open **SSMS**, connect to `localhost`, and see
      **AdventureWorks2019** and **WideWorldImporters**.
- [ ] **5. Azure SQL (DMS target)** — in the portal you see your **Azure SQL server**
      (`mhlabu01-sqlsrv-…`) and note its FQDN (used in Challenge 2).
- [ ] **6. Azure SQL Managed Instance (MI Link target)** — in the portal you see your
      **Managed Instance** (`mhlabu01-sqlmi-…`); it may still be provisioning — ask the
      facilitator if it does not appear yet.
- [ ] **7. Key Vault** — you open your **Key Vault** (`mhlabu01kv…`) and read the
      `vm-admin-password` secret. You have the **Key Vault Secrets User** role on your RG.

If all checks are green, you are ready for Challenge 1. 🎉

## Credentials you will handle

Be careful: there are **two different passwords** you must not confuse. All of them are stored
in your personal **Azure Key Vault** (`mhlabu01kv…`); you have **Key Vault Secrets User** access
to read them.

| Credential | Used for | Where to find it |
| --- | --- | --- |
| Entra ID user (`<prefix>user<NN>@…`) | Azure portal and VM sign-in | **Temporary** password from facilitator (`Temporal01!`); change at first sign-in. Also in Key Vault `student-password`. |
| VM local admin (`mhadmin`) | Alternate VM sign-in through Bastion | Key Vault secret `vm-admin-password` |
| Source SQL login (`sa` / `sqladmin`) | SQL connection inside the source VM | Key Vault secret `vm-admin-password` (equals the VM admin password) |
| Azure SQL / MI login (`sqladmin`) | Connection to the Azure targets | Key Vault secret `sql-admin-password` |

> The **source** SQL login and the **Azure SQL** login are **different passwords** — `vm-admin-password`
> vs `sql-admin-password` in your Key Vault.
