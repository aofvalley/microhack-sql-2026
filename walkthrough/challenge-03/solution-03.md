# Solution 3 — Managed Instance Link migration

[Previous Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-04/solution-04.md)

> **Owner:** _to be assigned_ — this walkthrough is a placeholder. The branch owner for
> Challenge 3 should expand each step with portal screenshots, exact CLI / PowerShell commands,
> and validation outputs.

## Outline (to be expanded)

1. Confirm prerequisites on the source SQL Server 2019/2022 (version, trace flags, AG feature).
2. Generate or reuse a Database Master Key and TDE certificate on the source.
3. Create the database mirroring endpoint on the source.
4. Provision (or reuse) the target Azure SQL Managed Instance.
5. Create the MI link from the Azure portal wizard (or `New-AzSqlInstanceLink`).
6. Monitor link health and replication lag.
7. Perform a planned failover and validate the database is writable on MI.
8. Optional: drop the link to make the cutover permanent.

---

[Previous Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-04/solution-04.md)
