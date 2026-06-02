# Solution 0 — SQL Server access setup

**[Home](../../Readme.md)** - [Next Solution](../challenge-01/solution-01.md)

> **Owner:** _to be assigned_ — this walkthrough is a placeholder. The branch owner for
> Challenge 0 should expand each step with portal screenshots, exact CLI commands, and any
> tenant-specific values.

## Outline (to be expanded)

1. Sign in to Azure CLI and Az PowerShell against the lab tenant and subscription.
2. Connect to the lab JumpBox through Azure Bastion.
3. From the JumpBox, open SSMS 20+ and the VS Code MSSQL extension.
4. Connect to the **SQL Server 2019** instance (the single lab source used across Challenges 1–5).
   - Confirm the restored sample databases (AdventureWorks2019 / WideWorldImporters /
     AdventureWorksDW2019) are online.
   - Capture host name, port, login, and password for later challenges.
5. Validate outbound paths required by later challenges (Azure Migrate appliance, DMS Self-hosted
   Integration Runtime, storage account, MI Link endpoints).
6. Document any blockers and hand off the validated environment to the rest of the team.

## Hand-off checklist

- [ ] Tenant ID and subscription ID confirmed
- [ ] Resource group and region noted
- [ ] JumpBox name + Bastion connection working
- [ ] SQL Server 2019 instance reachable, sysadmin credentials available
- [ ] Sample databases (AdventureWorks2019 / WideWorldImporters / AdventureWorksDW2019) online
- [ ] Connection strings stored in the shared secure note

---

[Previous Challenge] - **[Home](../../Readme.md)** - [Next Solution](../challenge-01/solution-01.md)
