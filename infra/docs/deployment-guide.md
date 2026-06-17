# Deployment guide

This guide is for facilitators deploying the infrastructure for the MicroHack SQL 2026 lab.

## 1. Sign in and select the subscription

```powershell
Set-Location <repo-root>\infra
az login --tenant <your-tenant-id>
az account set --subscription <your-subscription-id>
az account show --output table
```

Required permissions are Owner, or Contributor plus User Access Administrator. You also need permission to create Entra ID users, and — to map each student as the Entra ID administrator of their SQL Managed Instance — to manage the **Directory Readers** role (Global Administrator or Privileged Role Administrator).

### Resource providers (one-time, subscription level)

The lab needs these resource providers registered on the subscription: `Microsoft.DataMigration`
(Challenge 2 DMS), `Microsoft.Sql`, `Microsoft.KeyVault`, `Microsoft.Compute`, `Microsoft.Network`.
`deploy.ps1` registers any that are missing automatically at the start of a deployment. Students
**cannot** do this themselves — they only get Contributor on their own resource group — so if you
deploy without `deploy.ps1`, register them once with:

```powershell
foreach ($p in 'Microsoft.DataMigration','Microsoft.Sql','Microsoft.KeyVault','Microsoft.Compute','Microsoft.Network') { az provider register --namespace $p }
```

## 2. Choose deployment settings

Main template: `bicep\main.bicep`  
Scope: subscription

Common settings:

| Setting | Typical value | Notes |
| --- | --- | --- |
| `userCount` | `30` | Default cohort size. Use a smaller number for pilots. |
| `startUserIndex` | `1` | First student index. |
| `location` | `westeurope` | Confirm quota and service availability. |
| `namePrefix` | `mh` | Used in resource and user names. |
| `deploySourceVm` | `true` | Required for both SQL Server source VMs (SQL 2019 + SQL 2025). |
| `deploySqlMi` | `true` | Required for Challenge 3; slow and costly. |
| `vmSize` | `Standard_D4s_v5` | Default VM size. |
| `autoShutdownTime` | `1900` | UTC VM auto-shutdown time. |

## 3. Run a what-if

Use what-if before a large deployment, especially when `userCount=30`.

```powershell
az deployment sub what-if `
  --location westeurope `
  --template-file .\bicep\main.bicep `
  --parameters userCount=1 `
               startUserIndex=1 `
               location=westeurope `
               namePrefix=mh `
               deploySourceVm=true `
               deploySqlMi=false
```

For secure parameters such as `vmAdminPassword` and `sqlAdminPassword`, provide values using your normal secure parameter process or the deployment script.

## 4. Deploy with the CLI script

`deploy.ps1` requires only `-SubscriptionId`. The source-VM setup script
(`bicep\scripts\setup-source-vm.ps1`) is delivered automatically: because this
repo is **private**, `deploy.ps1` stages the local script in a per-subscription
storage account (`rg-<prefix>-staging`) and hands the VM Custom Script Extension a
short-lived Azure AD **user-delegation SAS** URL — no public raw GitHub URL is used.
VM and SQL passwords are generated if not supplied. Pass `-SetupScriptUri <url>`
only if you want to override delivery with your own reachable URL.

```powershell
pwsh .\scripts\deploy.ps1 `
  -SubscriptionId <your-subscription-id> `
  -UserCount 30 `
  -StartIndex 1 `
  -Location spaincentral `
  -Prefix mh `
  -CreateUsers
```

Add `-WhatIf` to preview without deploying. Useful switches: `-CreateUsers` (create Entra users

+ RBAC), `-DeploySqlMi false` (skip Managed Instance), `-SecurityControlIgnore` (tag SQL/MI to
satisfy MCAPS deny policies when testing in a Microsoft-internal tenant).

> **Microsoft Entra ID authentication on Azure SQL.** The Azure SQL logical server is configured
> for **both** SQL authentication and **Microsoft Entra ID** authentication. By default `deploy.ps1`
> sets the signed-in user as the server's Entra ID administrator; pass `-SqlEntraAdmin <UPN>` to use
> a different account. If the Entra admin cannot be resolved (for example a Graph/CAE error), the
> deployment degrades gracefully to SQL-only authentication so a large rollout is not blocked.

Recommended rollout:

1. Deploy `-UserCount 1 -DeploySqlMi false` to validate the path.
2. Deploy a small batch with SQL MI if Challenge 3 is in scope.
3. Deploy the full cohort only after quota and cost are confirmed.

## 5. Deploy with the web UI

```powershell
Set-Location <repo-root>\infra
Invoke-Item .\web\public\index.html
```

In the UI:

1. Select the tenant and subscription.
2. Choose `location`, `namePrefix`, `userCount`, and `startUserIndex`.
3. Decide whether to deploy the source VMs and SQL MI.
4. Review the generated plan.
5. Start deployment and monitor progress.

## 6. Add students later (incremental)

Subscription-scoped deployments are incremental and resource names derive from the student
index, so you can add students after the initial rollout without touching the existing ones.
Use `add-user.ps1`, which auto-detects the next free index from the existing
`rg-<prefix>-user*` groups:

```powershell
# You already deployed 20 students; a 21st arrives. This provisions index 21 + their Entra user:
pwsh .\scripts\add-user.ps1 `
  -SubscriptionId <your-subscription-id> `
  -Prefix mh `
  -CreateUsers
```

Options: `-Count N` to add several at once, `-StartIndex N` to force the index instead of
auto-detecting, `-WhatIf` to preview. The web UI offers the same flow via the **Detect next
free index** button (it sets the *Start index* automatically). Every added environment includes
an Azure SQL Managed Instance by default.

### Adding a Managed Instance to an existing environment

If a student environment was deployed without an MI (for example `-DeploySqlMi false` was used, or a
region lacked MI capacity at the time), add one later without touching the existing VMs, Azure SQL
server or Key Vault:

```powershell
pwsh -c "& .\scripts\add-mi.ps1 -UserIndexes @(17,18,19,20,21,22) `
  -SubscriptionId <your-subscription-id> -Prefix mh"
```

`add-mi.ps1` reads each student's SQL admin credentials from their Key Vault and deploys
`bicep\add-mi.bicep`, which adds only the delegated `snet-mi` subnet (default `10.0.4.0/24`), the MI
NSG (incl. inbound TCP 3342), the route table and the Managed Instance. Resource groups that already
have an MI are skipped. The instance is created in the resource group's region — check that region's
`SubscriptionSQLManagedInstanceStandardSeriesVCoreQuota` (4 vCores per instance) first. MI
provisioning takes several hours; afterwards run `scripts\set-mi-entra-admin.ps1` for the same
indexes to map each student as the MI Entra ID administrator.


## 7. Create users

The deployment model includes one Entra ID user per student, created by `scripts\create-users.ps1`, with these RBAC assignments on the student's resource group:

+ **Contributor** — manage resources inside their own resource group.
+ **Key Vault Secrets User** — read the lab credentials stored in their per-student Key Vault.
+ **Virtual Machine Administrator Login** — sign in to the source VMs through Bastion.
+ **Security Admin** — manage Microsoft Defender for Cloud / security configuration within their own resource group (used by the Azure Migrate assessment in Challenge 1).

Each user is created with a **temporary password** (default `Temporal01!`, override with
`-InitialPassword`) and **must change it at first sign-in** (`forceChangePasswordNextSignIn=true`).
MFA registration at first sign-in is enforced by the tenant's **Security Defaults** or a
**Conditional Access** policy — confirm one of these is enabled in the lab tenant if you require MFA
(it is on by default in most new tenants).

`deploy.ps1 -CreateUsers` runs this automatically. To run it on its own (it discovers the
tenant domain via Microsoft Graph if `-TenantDomain` is omitted, and needs the Graph permission
to create users):

```powershell
pwsh .\scripts\create-users.ps1 `
  -UserCount 30 -StartIndex 1 -Prefix mh `
  -TenantDomain <your-tenant>.onmicrosoft.com `
  -SubscriptionId <your-subscription-id> `
  -AssignRbac
```

Record generated usernames and initial passwords securely (written to `out\users.csv`). Do not commit credentials to the repository.

### Managed Instance Entra ID administrator

Each student is also set as the **Microsoft Entra ID administrator of their own SQL Managed
Instance**, giving them admin rights over every database on that instance. `deploy.ps1` performs
this automatically (after `create-users.ps1`, when an MI is deployed) by invoking
`scripts\set-mi-entra-admin.ps1`.

> **Prerequisite — Directory Readers.** Setting an Entra admin on a Managed Instance fails with
> `ServicePrincipalLookupInAadFailedIdentityForbidden` unless the MI's system-assigned managed
> identity holds the Entra **Directory Readers** role. The script grants this role to each MI
> identity first (it can take a couple of minutes to propagate), then sets the student admin once
> the instance is `Ready`. Managing this directory role requires the caller to be **Global
> Administrator** or **Privileged Role Administrator** in the tenant.

To run it on its own (for example to map instances that finished provisioning after the initial
deploy):

```powershell
pwsh .\scripts\set-mi-entra-admin.ps1 `
  -UserCount 30 -StartIndex 1 -Prefix mh `
  -TenantDomain <your-tenant>.onmicrosoft.com `
  -SubscriptionId <your-subscription-id> `
  -WaitForReady
```

Resource groups without a Managed Instance are skipped automatically. `-WaitForReady` keeps polling
each instance (default up to 8 hours) until it reaches `Ready` before assigning the admin.

## 8. Distribute credentials

All lab credentials are also stored in each student's per-student **Azure Key Vault**
(`<prefix>u<NN>kv<hash>`) as secrets `student-username`, `student-password`, `vm-admin-username`,
`vm-admin-password`, `sql-admin-login` and `sql-admin-password`. `student-username`/`student-password`
record the student's Entra ID sign-in and the **initial temporary** password (the student changes it
at first sign-in); the `vm-admin-*` and `sql-admin-*` secrets are the durable passwords needed to
reach the machines and SQL. Students read them with their Key Vault Secrets User role, for example:

```powershell
az keyvault secret show --vault-name <prefix>u01kv<hash> --name vm-admin-password --query value -o tsv
```

For each student, provide:

+ Entra ID username
+ Initial password and password reset instructions, if applicable
+ Assigned resource group, for example `rg-mh-user01`
+ Their Key Vault name (lab passwords live here)
+ Source VM name or portal instructions
+ Lab repository link: <https://github.com/aofvalley/microhack-sql-2026>

Students should access the VM using Azure Bastion from the Azure portal.

## 9. Validate each environment

For a sample of students, verify:

| Check | Expected result |
| --- | --- |
| Student sign-in | Student can sign in to the tenant. |
| RG access | Student sees only the expected assigned lab resources. |
| Bastion RDP | Student can open browser-based RDP to both source VMs. |
| VM setup | SSMS 20, Azure CLI, VS Code, and MSSQL extension are installed on both VMs. |
| SQL source | AdventureWorks2019 and WideWorldImporters are restored on both VMs. |
| Azure SQL logical server | Public endpoint, firewall and SQL + Microsoft Entra ID authentication are configured; no target DB is pre-created. |
| SQL MI | Present only when `deploySqlMi=true`; public endpoint enabled; the student is its Entra ID administrator. |
| Auto-shutdown | Both source VMs have auto-shutdown configured for `1900` UTC. |

## 10. Power VMs off and on without destroying them

If you deploy the environments ahead of time (for example the evening before the lab) and want to
power the VMs down overnight to save cost, use the non-destructive cohort scripts. They only
start / `deallocate` the VMs — resource groups, disks, Azure SQL and Managed Instances are kept.

```powershell
# End of the day: stop (deallocate) all student VMs across rg-<prefix>-user*
pwsh .\scripts\stop-labs.ps1 -SubscriptionId <id> -Prefix mh

# Next morning, before attendees arrive: start them again
pwsh .\scripts\start-labs.ps1 -SubscriptionId <id> -Prefix mh
```

Both scripts accept `-StartIndex` / `-UserCount` to target a range, and `-Wait` to block until the
operation finishes. The source VMs also auto-shutdown at `1900` UTC, so run `start-labs.ps1` each
morning. Managed Instances cannot be deallocated and keep billing while they exist.

## 11. Tear down

After the lab:

```powershell
pwsh .\scripts\cleanup.ps1 -SubscriptionId <id> -Prefix mh -All -Force
```

A full teardown (`-All`) also deletes the shared staging resource group
(`rg-<prefix>-staging`) that holds the setup-script storage account. When cleaning up
only specific students, add `-IncludeStaging` if you also want to remove that staging
group.

Alternatively, delete individual student resource groups such as `rg-mh-user01` to clean up one
environment. Ensure Entra ID users and RBAC assignments are also removed according to the cleanup
script's behavior.

## Troubleshooting

### Custom Script Extension or database restore failed

Check the source VM setup logs under:

```text
C:\Lab
```

Also inspect the VM extension status in Azure:

```powershell
az vm extension list `
  --resource-group rg-mh-user01 `
  --vm-name <source-vm-name> `
  --output table
```

> **Script delivery (private repo).** The setup script is delivered to the Custom Script
> Extension via a storage account + Azure AD user-delegation SAS staged by `deploy.ps1`
> (`rg-<prefix>-staging`). If the CSE fails with a 404/403 downloading the script, the SAS
> may have expired (24h lifetime) or the staging storage account is missing — just re-run
> `deploy.ps1`/`add-user.ps1`, which re-stages the script and re-issues a fresh SAS.

### SQL Server IaaS extension issues

Check SQL VM registration and extension state:

```powershell
az sql vm list --resource-group rg-mh-user01 --output table
az sql vm show --resource-group rg-mh-user01 --name <source-vm-name> --output jsonc
```

If the extension is still provisioning, wait and re-check before re-running deployment steps.

### Azure SQL Managed Instance takes a long time

This is expected. Plan for **3-6 hours**. Large cohorts deploy many MIs, so quota, regional capacity, and subscription limits can add delays or failures.

Mitigation:

+ Use `deploySqlMi=false` for initial source VM and Azure SQL Database preparation.
+ Deploy SQL MI earlier than the lab start if Challenge 3 is required.
+ Deploy in smaller batches using `userCount` and `startUserIndex`.

### Students cannot access the VM through Bastion

Verify:

+ The student has Virtual Machine Administrator Login on the correct resource group.
+ The student has Contributor on the correct resource group.
+ Azure Bastion exists in `AzureBastionSubnet`.
+ The VM is running.
+ NSG rules allow Bastion-required traffic.

### Student cannot read Key Vault secrets

Verify:

+ The student has the **Key Vault Secrets User** role on their resource group (or the vault).
+ They query the correct vault name (`<prefix>u<NN>kv<hash>`), shown in `out\connection-guide.md`.
+ RBAC role assignments can take a few minutes to propagate after `create-users.ps1`.

### Student cannot connect to Azure SQL logical server

Verify:

+ The logical server public endpoint is enabled.
+ Firewall rules allow Azure services and the student.
+ The student created the target database for Challenge 2.
+ Credentials use the configured `sqlAdminLogin` and `sqlAdminPassword` or the intended lab credential flow.
