# Solution 0 — Environment access (facilitator)

**[Home](../../Readme.md)** - [Next Solution](../challenge-01/solution-01.md)

This walkthrough is for **facilitators**. It complements
[Challenge 0](../../challenges/challenge-00.md) with the provisioning context and the exact
checks to run if an attendee is blocked. Attendees follow the challenge; facilitators own the
deployment.

## Environment model

Each attendee has a fully isolated resource group `rg-<prefix>-user<NN>` (e.g. `rg-mhlab-user01`)
provisioned ahead of time. Per user it contains:

- An **Entra ID user** `<prefix>user<NN>@<tenant>` with a **temporary** password (default
  `Temporal01!`, `forceChangePasswordNextSignIn = true`) and MFA registration at first sign-in.
- **RBAC on the RG:** Contributor + Key Vault Secrets User + Virtual Machine Administrator Login.
- A **source VM** (Windows Server 2022 + SQL Server 2019 Developer) with SSMS 20, Azure CLI and
  VS Code, plus **AdventureWorks2019** and **WideWorldImporters** restored and online.
- **Azure Bastion** for VM access (public networking; no private endpoints).
- A per-user **Key Vault** holding `student-username/password`, `vm-admin-username/password`,
  `sql-admin-login/password`.
- An **Azure SQL logical server** (DMS target, Challenge 2) and an **Azure SQL Managed Instance**
  (MI Link target, Challenge 3), both public-endpoint.

## Provisioning

The infrastructure and users are deployed and removed with the automation owned by the
Challenge 0 / infra owner (Bicep + PowerShell + an optional web UI). It is parameterised by the
number of attendees and supports adding a single extra environment on demand.

> ℹ️ **Coordination note:** this per-student design (one RG / Bastion / Key Vault / SQL MI **per
> user**, Entra users) differs from the shared-JumpBox `infra/` currently in this repo. Agree as
> a team whether it **replaces** the existing `infra/` or lands as an alternative before merging
> any infrastructure. See `team-merge/MERGE-GUIDE.md` in the infra source for the full plan.

## Verification checklist (per attendee)

1. **Identity** — `forceChangePasswordNextSignIn = true`, MFA registered, RG visible to the user.
2. **Key Vault** — six secrets present; the user can read them (Key Vault Secrets User).
3. **Bastion** — connects with `mhadmin` / `vm-admin-password`.
4. **Source SQL** — SSMS at `localhost`; both sample databases online.
5. **Azure SQL** — logical server reachable; FQDN captured for Challenge 2.
6. **Managed Instance** — `Ready` (or note that it is still provisioning, up to 3–6 h).

## Useful CLI checks

```powershell
# All resources in an attendee RG
az resource list -g rg-mhlab-user01 -o table

# Read the VM password the attendee needs
az keyvault secret show --vault-name <kv-name> --name vm-admin-password --query value -o tsv

# Confirm the Entra user must change password at first sign-in
az ad user show --id mhlabuser01@<tenant> --query userPrincipalName -o tsv
```
