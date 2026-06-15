# MicroHack SQL 2026 scripts

PowerShell 7 wrappers for deploying and operating the per-student Azure lab. Run from the repo
root or by full script path. The scripts create `out\` for logs, deployment JSON, CSVs, and the
connection guide.

> `out\users.csv` and `out\connection-guide.md` intentionally contain lab credentials. Store and
> share them carefully. SQL Managed Instance can take 3-6 hours to deploy and is costly; disable it
> with `-DeploySqlMi:$false` when not needed.

## Deploy

```powershell
pwsh .\scripts\deploy.ps1 `
  -SubscriptionId '<your-subscription-id>' `
  -TenantId '<your-tenant-id>' `
  -UserCount 30 `
  -StartIndex 1 `
  -Location 'spaincentral' `
  -Prefix 'mh' `
  -CreateUsers
```

Preview only:

```powershell
pwsh .\scripts\deploy.ps1 -SubscriptionId '<your-subscription-id>' -WhatIf
```

> The source-VM setup script is staged automatically (storage account + Azure AD
> user-delegation SAS) so the Custom Script Extension works against this private repo.
> Pass `-SetupScriptUri <url>` only to override delivery with your own reachable URL.
>
> **MCAPS / internal-tenant testing.** Add `-SecurityControlIgnore` to tag Azure SQL / SQL MI with
> `SecurityControl=Ignore` and satisfy MCAPS governance deny policies. On the test subscription, SQL
> provisioning is region-restricted; `swedencentral` works while `westeurope`/`northeurope`/`eastus2`
> were blocked. Validated example:
>
> ```powershell
> pwsh .\scripts\deploy.ps1 -SubscriptionId '<your-subscription-id>' `
>   -UserCount 1 -Location swedencentral -Prefix mh -DeploySqlMi false -DeploySourceVm false `
>   -SecurityControlIgnore
> ```

## Create or update lab users

Get a verified domain first if needed:

```powershell
az rest --method get --url https://graph.microsoft.com/v1.0/domains --query "value[?isVerified].id" -o tsv
```

Create users and assign per-resource-group access:

```powershell
pwsh .\scripts\create-users.ps1 `
  -UserCount 30 `
  -StartIndex 1 `
  -TenantDomain 'contoso.onmicrosoft.com' `
  -Prefix 'mh' `
  -SubscriptionId '<your-subscription-id>' `
  -AssignRbac
```

## Start / stop labs (non-destructive)

Power all student VMs on or off without deleting anything — useful when you deploy the labs ahead of
time and leave them running across multiple days.

```powershell
# Stop (deallocate) every student VM under rg-<prefix>-user*
pwsh .\scripts\stop-labs.ps1 -SubscriptionId '<your-subscription-id>' -Prefix 'mh'

# Start (power on) every student VM
pwsh .\scripts\start-labs.ps1 -SubscriptionId '<your-subscription-id>' -Prefix 'mh'
```

Both scripts auto-discover `rg-<prefix>-user*` groups (or use `-StartIndex` / `-UserCount` for a
range) and start/`deallocate` every VM in them. Add `-Wait` to block until the operation finishes.
Each script starts/stops **both** source VMs (SQL 2019 and SQL 2025) per student. Managed Instances
are not affected (they cannot be deallocated).

## Cleanup

Delete a known count:

```powershell
pwsh .\scripts\cleanup.ps1 `
  -SubscriptionId '<your-subscription-id>' `
  -Prefix 'mh' `
  -UserCount 30 `
  -StartIndex 1 `
  -Force
```

Delete **all** lab resource groups for a prefix (auto-discovers `rg-<prefix>-user*`, no count needed):

```powershell
pwsh .\scripts\cleanup.ps1 -SubscriptionId '<your-subscription-id>' -Prefix 'mh' -All -Force
```

Delete lab users too:

```powershell
pwsh .\scripts\cleanup.ps1 -SubscriptionId '<your-subscription-id>' -Prefix 'mh' -All -DeleteUsers -TenantDomain 'contoso.onmicrosoft.com' -Force
```

## Parameters

| Script | Parameter | Default | Notes |
| --- | --- | --- | --- |
| deploy | SubscriptionId | required | Azure subscription to target. |
| deploy | TenantId | optional | Used to warn if the current CLI tenant differs. |
| deploy/create/cleanup | UserCount | 30 | Number of student environments/users. |
| deploy/create/cleanup | StartIndex | 1 | First user index; names are zero-padded. |
| deploy | Location | westeurope | Subscription deployment location and Bicep location parameter. |
| deploy/create/cleanup | Prefix | mh | Lowercase prefix for users and resource groups. |
| deploy | VmAdminPassword, SqlAdminPassword | generated | Strong passwords are generated if omitted. |
| deploy | DeploySqlMi, DeploySourceVm | true | Passed directly to Bicep (accepts true/false). |
| deploy | SetupScriptUri | optional | Override the staged setup-script delivery with your own reachable URL. Omit to auto-stage via storage + user-delegation SAS. |
| deploy | StagingStorageAccount | optional | Override the auto-generated staging storage account name (3-24 lowercase alnum). |
| deploy | SecurityControlIgnore | false | Tag SQL/MI with `SecurityControl=Ignore` for MCAPS deny-policy bypass when testing. |
| deploy | SqlEntraAdmin | signed-in user | UPN to set as the Azure SQL server's Microsoft Entra ID administrator (alongside SQL auth). Falls back to SQL-only if it cannot be resolved. |
| deploy | CreateUsers, SkipUsers, WhatIf | false | User creation runs after a successful deploy unless skipped. |
| create-users | TenantDomain | required | Verified Entra domain for UPNs. |
| create-users | Password | generated | Existing users are not reset; blank password in CSV means skipped existing user. |
| create-users | AssignRbac | false | Adds Reader and Virtual Machine Administrator Login per user RG. |
| cleanup | All | false | Discover and delete every `rg-<prefix>-user*` group (ignores UserCount/StartIndex). |
| cleanup | DeleteUsers, TenantDomain, Force | false | `TenantDomain` is required when deleting users; `Force` skips confirmation. |
| start-labs/stop-labs | SubscriptionId, Prefix | required / mh | Discover `rg-<prefix>-user*` and start / deallocate every VM. |
| start-labs/stop-labs | StartIndex, UserCount, Wait | auto / false | Target an index range; `-Wait` blocks until the operation finishes. |

## Bicep parameters file

Use `scripts\parameters.example.json` as a placeholder-only example for:

```powershell
az deployment sub create --location westeurope --template-file .\bicep\main.bicep --parameters '@scripts\parameters.example.json'
```
