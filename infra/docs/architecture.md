# Architecture

This repository provisions isolated Azure environments for the MicroHack SQL 2026 lab. Each
student receives a dedicated resource group, VNet, identity, SQL Server source VM, Azure SQL
logical server, and optionally Azure SQL Managed Instance.

## Per-student network diagram

![Per-student architecture for user01](images/architecture.png)

The diagram above shows a single student's environment (`user01`). The same layout is created
for every student, fully isolated in its own resource group. The text diagram below is an
accessible fallback.

```text
rg-<prefix>-user<NN>

                    Internet / Facilitator / Student browser
                                  |
                                  v
                         Public endpoints by design
                                  |
        +--------------------------------------------------+
        | VNet 10.0.0.0/16                                |
        |                                                  |
        |  +----------------------+                        |
        |  | AzureBastionSubnet   |                        |
        |  | Azure Bastion        |---- Browser-based RDP -+
        |  +----------------------+                        |
        |               |                                  |
        |               v                                  |
        |  +----------------------+                        |
        |  | snet-sql             |                        |
        |  | Source VM            |                        |
        |  | Windows Server 2022  |                        |
        |  | SQL Server 2019 Dev  |                        |
        |  +----------------------+                        |
        |               |                                  |
        |               | DMS / migration traffic          |
        |               v                                  |
        |  +----------------------+                        |
        |  | snet-mi              |                        |
        |  | Delegated subnet     |                        |
        |  | Azure SQL MI         |                        |
        |  +----------------------+                        |
        +--------------------------------------------------+

        Azure SQL logical server: public endpoint, firewall enabled
        Azure Key Vault: per-student, RBAC-authorized, stores all credentials
        Log Analytics workspace: per-student, diagnostics/telemetry for the lab resources
        Entra ID user: Contributor + Key Vault Secrets User + VM Admin Login, scoped to this resource group
```

## Credentials and Key Vault

Every student resource group contains a dedicated, RBAC-authorized **Azure Key Vault**
(`<prefix>u<NN>kv<hash>`). The deployment writes the following secrets into it:

| Secret name | Contents |
| --- | --- |
| `student-username` | The student's Azure (Entra ID) sign-in (`<prefix>user<NN>@…`). |
| `student-password` | The student's Azure (Entra ID) sign-in password (also handed out for the first login). |
| `vm-admin-username` | Local administrator username for the source VM. |
| `vm-admin-password` | Local administrator / SQL `sa` password for the source VM. |
| `sql-admin-login` | Administrator login for the Azure SQL server and Managed Instance. |
| `sql-admin-password` | Administrator password for the Azure SQL server and Managed Instance. |

The deploying facilitator (Owner/Contributor on the subscription) can write these secrets via the
ARM management plane regardless of RBAC mode. Each student is granted **Key Vault Secrets User**
on their resource group, so they can read — but not change — their own credentials. Purge
protection is disabled so `scripts\cleanup.ps1` can fully remove each vault during teardown.

## Per-student components

| Component | SKU / configuration | Purpose | Lab challenge support |
| --- | --- | --- | --- |
| Resource group | `rg-<prefix>-user<NN>` | Isolation, RBAC boundary, teardown unit. | Challenges 0-5 |
| Entra ID user | Created by `scripts\create-users.ps1` | Student sign-in identity with scoped access. | Challenges 0-5 |
| RBAC assignments | Contributor + Key Vault Secrets User + VM Administrator Login, scoped to the student RG | Manage own RG, read Key Vault secrets, sign in via Bastion. | Challenges 0-5 |
| Azure Key Vault | One per student, RBAC-authorized, public endpoint | Stores all lab credentials (VM admin + SQL admin). Students read them with their Key Vault Secrets User role. | Challenges 0-5 |
| Log Analytics workspace | One per student (`<prefix>u<NN>-law`), PerGB2018, 30-day retention | Collects diagnostics/telemetry for the student's lab resources. | Challenges 0-5 |
| Source VM | `Standard_D4s_v5` default | SQL Server 2019 source environment. | Assessment and migration source |
| VM image | Windows Server 2022 + SQL Server 2019 Developer, `sql2019-ws2022:sqldev-gen2` | Matches the modernization source workload. | Challenges 1-3 |
| Custom Script Extension | Restores AdventureWorks2019 and WideWorldImporters; installs SSMS 20, Azure CLI, VS Code | Prepares repeatable student workstation and SQL source. | Challenges 0-5 |
| Public IP | Public VM networking | Simple lab connectivity model. | Challenges 0-5 |
| Azure Bastion | One per resource group | Browser-based RDP to the source VM without distributing direct RDP steps. | Challenges 0-5 |
| Azure SQL logical server | Public endpoint, firewall allowing Azure services and the student | Target host where students create the database used by DMS migration. | Challenge 2 |
| Azure SQL databases | None pre-created | Students create the target database themselves. | Challenge 2 |
| Azure SQL Managed Instance | GP_Gen5, 4 vCores, public endpoint enabled | Destination for Managed Instance Link migration. | Challenge 3 |
| VNet | `10.0.0.0/16` per student | Private address space local to the student environment. | Challenges 0-5 |
| `snet-sql` | VM subnet | Hosts the source VM. | Challenges 1-3 |
| `AzureBastionSubnet` | Bastion subnet | Required subnet for Azure Bastion. | Challenges 0-5 |
| `snet-mi` | Delegated to `Microsoft.Sql/managedInstances` | Hosts Azure SQL Managed Instance. | Challenge 3 |

## Network and NSG model

| Network element | Scope | Rules / behavior | Reason |
| --- | --- | --- | --- |
| VNet | Per student, `10.0.0.0/16` | No shared VNet between students. | Prevents cross-student network access and simplifies teardown. |
| `snet-sql` | Source VM subnet | Allows required VM and Bastion traffic. | Student can administer the SQL Server source VM. |
| `AzureBastionSubnet` | Bastion subnet | NSG allows Azure Bastion-required traffic. | Enables browser-based RDP. |
| `snet-mi` | SQL MI subnet | Delegated to `Microsoft.Sql/managedInstances`; NSG allows MI-required ports. | Required for Azure SQL Managed Instance deployment and operation. |
| Azure SQL logical server firewall | Logical server | Public endpoint with firewall rule allowing Azure services and the student. | Keeps Challenge 2 simple and avoids private endpoint setup. |
| Azure SQL MI public endpoint | Managed instance | Public endpoint enabled. | Supports the lab design decision to avoid private networking complexity. |

## Isolation model

- Every student gets a separate resource group.
- Every student gets a separate VNet, even though each VNet uses the same `10.0.0.0/16` address space.
- RBAC is scoped to the student's resource group (Contributor + Key Vault Secrets User + VM Admin Login).
- Each student gets a dedicated, RBAC-authorized Key Vault holding their credentials.
- There is no intentional cross-student routing, peering, or shared database target.
- Teardown can be performed per student by deleting the student's resource group and user assignments, or for the whole cohort with `scripts\cleanup.ps1`.

This model is more resource-intensive than a shared environment, but it avoids noisy-neighbor issues, prevents accidental cross-student access, and makes troubleshooting easier for facilitators.

## Adding students incrementally

Because resource group and resource names derive from the student index, each deployment only
creates the indexes it targets and never overwrites existing students. This makes it safe to
add students after the initial rollout — for example, you deployed 20 students and a 21st
arrives:

```powershell
# Auto-detect the next free index (here 21) and provision one more student + their Entra user:
pwsh .\scripts\add-user.ps1 -SubscriptionId <id> -Prefix mh -SetupScriptUri <url> -CreateUsers
```

`add-user.ps1` inspects the existing `rg-<prefix>-user*` groups, picks the next free index, and
calls `deploy.ps1` with that `startUserIndex`. The web UI offers the same flow with the
**Detect next free index** button. See the [deployment guide](deployment-guide.md) for details.

Every student environment includes an Azure SQL Managed Instance by default (`deploySqlMi=true`).
Set it to `false` only for dry runs or cohorts that skip Challenge 3.

## Design rationale

### Full per-student isolation

Dedicated resource groups and VNets give each student an independent environment for assessment,
migration, and validation. This keeps RBAC simple and allows individual environments to be reset
without impacting the cohort.

### Public networking

The lab intentionally uses public endpoints to reduce complexity. Private endpoints, DNS
forwarding, VNet peering, and jumpbox routing are valuable production patterns, but they add setup
and troubleshooting overhead that distracts from the SQL modernization learning objectives.

### SQL Managed Instance toggle

Azure SQL Managed Instance is required for the Managed Instance Link challenge, but it can take
**3-6 hours** to provision and is the largest cost driver. The `deploySqlMi` parameter allows
facilitators to skip it for dry runs, early setup, or cohorts that do not run Challenge 3.

## Mapping to lab challenges 0-5

| Lab challenge | Infrastructure support |
| --- | --- |
| Challenge 0: environment access and orientation | Entra ID user, RBAC, resource group, Key Vault (credentials), Bastion, source VM tooling. |
| Challenge 1: assess SQL Server 2019 source | Source VM with SQL Server 2019 Developer, restored AdventureWorks2019 and WideWorldImporters, SSMS 20, VS Code + MSSQL extension. |
| Challenge 2: migrate to Azure SQL Database with DMS | Azure SQL logical server with public endpoint and firewall; students create the target database. |
| Challenge 3: migrate to Azure SQL Managed Instance with MI Link | Azure SQL Managed Instance GP_Gen5 4 vCores in delegated subnet with public endpoint. |
| Challenge 4: validate and modernize | Source and target SQL platforms remain available for comparison, testing, and application/tooling exercises. |
| Challenge 5: cleanup and review | Per-student RG boundary and `scripts\cleanup.ps1` simplify teardown and post-lab cleanup. |
