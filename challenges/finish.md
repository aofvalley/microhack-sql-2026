# Finish

[Previous](challenge-05.md) - **[Home](../Readme.md)**

---

## Congratulations!

You have completed the **MicroHack — SQL Modernization (2026 edition)**.

---

## What you accomplished

| Challenge | Topic | Key skills |
|---|---|---|
| [Challenge 0](challenge-00.md) | SQL Server access setup | Source SQL Server connectivity, sample databases, lab credentials |
| [Challenge 1](challenge-01.md) | Assessment | Azure Migrate, SKU sizing, compatibility findings, readiness report |
| [Challenge 2](challenge-02.md) | DMS migration (SQL 2012 → Azure SQL DB) | Azure Database Migration Service, Self-hosted IR, schema + data migration |
| [Challenge 3](challenge-03.md) | Managed Instance Link migration | MI Link, near-zero-downtime cutover, distributed AG |
| [Challenge 4](challenge-04.md) | Monitoring & Performance | Query Store, Database Watcher, KQL, Azure Monitor for SQL |
| [Challenge 5](challenge-05.md) | Security & Defender | Microsoft Defender for SQL, TDE, auditing, Microsoft Entra auth |

---

## Clean up your resources

To avoid ongoing charges, delete all lab resources when you are done:

```powershell
# From the repo root
.\scripts\cleanup.ps1 -ResourceGroupName rg-sqlhack-<prefix>
```

The script removes the resource group and all resources inside it. Verify with:

```powershell
az group show --name rg-sqlhack-<prefix> --query provisioningState
```

Expected output: `"Deleting"` or a `ResourceGroupNotFound` error (group already gone).

---

## Next steps

- Explore the [Azure SQL Managed Instance documentation](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/)
- Try the [Managed Instance Link documentation](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-feature-overview)
- Review [Defender for SQL best practices](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-sql-introduction)
- Check the [facilitator guide](../docs/facilitator-guide.md) if you are running this for a team

---

## Feedback

Found a bug or have a suggestion? Open an issue on the
[microhack-sql-2026 repository](https://github.com/aofvalley/microhack-sql-2026/issues)
using the appropriate issue template.

---

Thank you for completing this MicroHack. See you next time!
