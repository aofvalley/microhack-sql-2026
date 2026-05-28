# FAQ

## Deployment

**Q: How long does deployment take?**
A: For 1-2 teams without SQL MI: 20-35 minutes. With SQL MI (-DeploySQLMI): add 4-6 hours for MI provisioning. Deploy MI the day before the session.

**Q: Can I run this without a SQL MI?**
A: Yes. -DeploySQLMI:$false (default) skips MI provisioning. Participants can still complete Challenge 1 using DMS or MI Link in read-scale mode.

**Q: What Azure regions work best?**
A: Regions with full VM + SQL MI quota: eastus, westeurope, southeastasia. Avoid regions with limited SQL MI availability.

**Q: Why does validate.ps1 fail on the SQL login check?**
A: The Custom Script Extension (CSE) may still be running. Check VM boot diagnostics in the Azure Portal or wait 5 minutes and re-run validate.ps1.

**Q: How do I clean up after the lab?**
A: Run .\scripts\cleanup.ps1 -ResourceGroupName rg-sqlhack-prefix. This deletes the entire resource group.

## Content

**Q: Which migration path should participants use?**
A: For SQL 2019/2022 sources, Managed Instance Link is the recommended 2026 path. DMS and LRS are also demonstrated and remain valid for older SQL Server versions.

**Q: Azure Data Studio is mentioned in my notes - is it still used?**
A: No. Azure Data Studio was retired on 28-Feb-2026. This edition uses SSMS 20+ and VS Code with the MSSQL extension.

**Q: Can I use a different sample database?**
A: The walkthroughs are written against AdventureWorks2019 and WideWorldImporters. Using a different database requires updating the walkthrough SQL scripts.

**Q: What SQL Server versions can be the migration source?**
A: This lab uses SQL Server 2022 Developer Edition as the source. MI Link requires SQL 2019 CU15+ or SQL 2022+. DMS and LRS support SQL 2008+.

## Security

**Q: Is there any production data in this lab?**
A: No. Only public sample databases (AdventureWorks2019, WideWorldImporters) are used.

**Q: Where are credentials stored?**
A: Generated credentials are written to scripts/out/team-credentials.csv on the machine running deploy.ps1. This file is .gitignored. Treat it as sensitive and delete it after the session.

**Q: Can participants access each other's VMs?**
A: No. NSG rules restrict RDP to each VM to Bastion-sourced connections only. There are no cross-team SQL logins provisioned.
