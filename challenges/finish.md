# Finish

[Previous](challenge-03.md) - **[Home](../Readme.md)**

---

## Congratulations!

You have completed the **MicroHack — SQL Modernization (2026 edition)**.

---

## What you accomplished

| Challenge | Topic | Key skills |
|---|---|---|
| [Challenge 1](challenge-01.md) | Assessment & Migration | DMS / MI Link / LRS, Azure SQL MI provisioning, database assessment |
| [Challenge 2](challenge-02.md) | Monitoring & Performance | Query Store, Database Watcher, KQL, Azure Monitor for SQL |
| [Challenge 3](challenge-03.md) | Security | Microsoft Defender for SQL, TDE, auditing, Azure AD auth |

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
