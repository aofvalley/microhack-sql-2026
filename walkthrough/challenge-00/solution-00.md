# Solution 0 — Introduction & environment access

**[Home](../../Readme.md)** - [Next Solution](../challenge-01/solution-01.md)

This is the worked solution for [Challenge 0](../../challenges/challenge-00.md). It walks through
every step an attendee performs, states the **expected result** of each one, and adds the
**facilitator** context (how the environment is provisioned and the exact checks to run when an
attendee is blocked). Attendees follow the challenge; facilitators own the deployment.

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
- A per-user **Log Analytics workspace** (`<prefix>u<NN>-law`) for diagnostics/telemetry.

## Provisioning

The infrastructure and users are deployed and removed with the automation in
[`infra/`](../../infra/README.md) (Bicep + PowerShell + an optional web UI). It is parameterised
by the number of attendees and supports adding a single extra environment on demand.

> ℹ️ **Deployment model:** each attendee gets a fully isolated environment — one resource group
> with its own Bastion, Key Vault, source VM, Azure SQL server, SQL Managed Instance and Log
> Analytics workspace, plus a dedicated Entra ID user. See
> [`infra/README.md`](../../infra/README.md) for the two deployment paths (CLI and web app) and
> the full parameter reference.

## Worked solution — step by step

Each step below maps 1:1 to the [challenge](../../challenges/challenge-00.md). The **Expected
result** is what the attendee should see when the step succeeds.

### Step 1 — Sign in to the Azure portal

The attendee opens <https://portal.azure.com> with `<prefix>user<NN>@<tenant>` and the temporary
password (`Temporal01!`), changes the password at first sign-in, and registers MFA.

**Expected result:** the Azure portal home page loads. The new password is set and MFA is
registered; the temporary password no longer works.

### Step 2 — Locate the resource group

The attendee searches **Resource groups** and opens `rg-mhlab-user<NN>`.

**Expected result:** exactly **one** resource group is visible and it contains the source VM,
Azure Bastion, the Azure SQL logical server, the SQL Managed Instance, the Key Vault and the Log
Analytics workspace. If more than one group is visible, the RBAC scope is wrong — see
[Troubleshooting](#troubleshooting).

### Step 2a — Read credentials from Key Vault

The attendee opens the Key Vault `mhlabu01kv…` → **Objects → Secrets** and reads the values (or
uses `az keyvault secret show`).

**Expected result:** six secrets are present (`student-username/password`,
`vm-admin-username/password`, `sql-admin-login/password`) and the attendee can read them with
their **Key Vault Secrets User** role. The password actually used to connect to the VM and to
the source SQL Server is `vm-admin-password`.

### Step 3 — Connect to the source VM with Bastion

The attendee opens `mhlabu01-srcvm` → **Connect → Bastion** and signs in with `mhadmin` and the
`vm-admin-password`.

**Expected result:** the Windows Server 2022 desktop of the source VM opens in a new browser tab.

### Step 4 — Connect to the source SQL Server with SSMS

Inside the VM the attendee opens SSMS, connects to `localhost` (Windows Authentication, or SQL
auth with `sa` / `sqladmin` and `vm-admin-password`), and expands **Databases**.

**Expected result:** SSMS connects and both **AdventureWorks2019** and **WideWorldImporters** are
present and **online**. If they are missing, the Custom Script Extension restore is still running
or failed — check `C:\Lab\setup-source-vm.log` on the VM.

### Step 5 — Identify the Azure SQL server (DMS target)

The attendee opens the Azure SQL logical server `mhlabu01-sqlsrv-…` and copies its FQDN.

**Expected result:** the server FQDN (`mhlabu01-sqlsrv-….database.windows.net`) is captured for
Challenge 2. No target database exists yet — the attendee creates it during the DMS migration.

### Step 6 — Identify the Azure SQL Managed Instance (MI Link target)

The attendee opens the SQL Managed Instance `mhlabu01-sqlmi-…` and checks its status.

**Expected result:** the Managed Instance is **Ready**. **MI provisioning can take 3–6 hours**, so
a *Creating* state early in the lab is normal — it is the destination for Challenge 3.

## Verification checklist (per attendee)

1. **Identity** — `forceChangePasswordNextSignIn = true`, MFA registered, RG visible to the user.
2. **Key Vault** — six secrets present; the user can read them (Key Vault Secrets User).
3. **Bastion** — connects with `mhadmin` / `vm-admin-password`.
4. **Source SQL** — SSMS at `localhost`; both sample databases online.
5. **Azure SQL** — logical server reachable; FQDN captured for Challenge 2.
6. **Managed Instance** — `Ready` (or note that it is still provisioning, up to 3–6 h).
7. **Log Analytics** — workspace `mhlabu01-law` present in the resource group.

## Useful CLI checks

```powershell
# All resources in an attendee RG
az resource list -g rg-mhlab-user01 -o table

# Read the VM password the attendee needs
az keyvault secret show --vault-name <kv-name> --name vm-admin-password --query value -o tsv

# Confirm the Entra user must change password at first sign-in
az ad user show --id mhlabuser01@<tenant> --query userPrincipalName -o tsv
```

## Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| More than one RG visible | RBAC assigned at the wrong scope | Re-run the role assignment scoped to the attendee RG only. |
| Cannot read Key Vault secrets | Role still propagating | Wait a few minutes; the user needs **Key Vault Secrets User** on the RG. |
| Bastion will not connect | Wrong VM credentials | Use `mhadmin` + `vm-admin-password` from Key Vault. |
| SSMS does not see the databases | Restore still running / failed | Check `C:\Lab\setup-source-vm.log` on the VM. |
| Managed Instance not visible | Slow provisioning | MI can take 3–6 hours; confirm the deployment finished. |
