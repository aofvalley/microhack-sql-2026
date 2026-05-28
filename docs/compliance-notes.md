# Compliance Notes

## Data residency

All resources are deployed to the Azure region specified by the -Location parameter in deploy.ps1.
No data leaves the selected region unless you configure cross-region replication (not done by default).

## Data in the lab

- Sample databases: AdventureWorks2019 and WideWorldImporters are public Microsoft sample databases.
  No PII or customer data is present.
- Team credentials: generated synthetic SQL logins (TEAM01_admin, etc.) scoped to the lab resource group.
- users.csv: maps user principal names to team numbers. This file should not contain real organizational data.
  Use the format in scripts/users.csv.example.

## Data leaving the tenant

- Log Analytics: VM performance metrics and SQL diagnostic logs are sent to the Log Analytics workspace
  within the same subscription and region.
- Defender for Cloud: security findings are stored in the Microsoft Defender for Cloud service,
  which is tenant-scoped and subject to your organization's data residency settings.
- No data is sent to third-party services.

## Credential handling

- The adminPassword parameter in deploy.ps1 is marked @Secure() and is never logged or stored in plain text.
- Generated team credentials are written to scripts/out/team-credentials.csv on the deploying machine only.
  This file is .gitignored. Delete it after the session.
- SQL logins use SQL authentication scoped to the lab databases. No domain credentials are used.

## MCAPS / Microsoft-internal notes

- This lab is designed for external use (partners, customers, community) and does not require
  an internal Microsoft subscription.
- If running in a Microsoft-managed tenant, ensure the subscription is not subject to policy
  that blocks public IP creation (Bastion requires a public IP) or SQL MI provisioning.
- For MCAPS engagements, document that only public sample databases are used and that
  no customer data enters the lab environment.
