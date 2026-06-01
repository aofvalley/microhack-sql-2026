# Challenge 1 — Image capture status

Screenshots captured from the **real lean lab** (`rg-microhack-sql-2026`, West Europe): one SQL
Server 2019 IaaS VM (`sqlvm-mh2026`) + one empty Azure SQL Database target
(`sqlsrvmh2026tin4vcwzqrg3k`, France Central) + `bastion-mh2026`.

## Captured (lean flow — used by `walkthrough/challenge-01/solution-01.md`)

| Step | File | What it shows |
|------|------|---------------|
| 01 | `c1-step-01-resource-group.png` | Resource group `rg-microhack-sql-2026` overview (all lab resources) |
| 02 | `c1-step-02-source-vm.png` | Source VM `sqlvm-mh2026` overview (SQL 2019, WS2022, D4s_v5) |
| 03 | `c1-step-03-sql-target.png` | Azure SQL logical server `sqlsrvmh2026tin4vcwzqrg3k` — empty Entra-only target |
| 04 | `c1-step-04-bastion-connect.png` | Bastion connect blade for `sqlvm-mh2026` |
| 2a | `c1-step-2a-azure-migrate-get-started.png` | Azure Migrate **Get started** landing page |
| 2b | `c1-step-2b-azure-migrate-create-project.png` | **Create project** form (subscription, RG, name, geography) |
| 2c | `c1-step-2c-azure-migrate-overview.png` | Project **Overview** hub (`migrate-mh2026`) |
| 2d | `c1-step-2d-azure-migrate-discovery-methods.png` | **Start discovery** dropdown (appliance / collector / import) |
| 2e | `c1-step-2e-azure-migrate-discover-appliance.png` | **Discover** appliance setup form (generate key + download .zip) |

> Steps 2a–2e are the genuine Azure Migrate portal flow for **2.1 (create project + discover)**,
> captured live in `migrate-mh2026`. The readiness / SKU / cost screens (2.3–2.4) require a fully
> registered appliance + a 15–30 min discovery window, so they are documented as text tables rather
> than fabricated screenshots; **Assessments** stays disabled until discovery populates the project.

## In-VM / client-side (not portal-screenshotable)

The assessment itself runs through the **Azure Migrate appliance registered on the VM** plus the
Azure Migrate blades in the portal. Document the in-VM appliance registration with text + the
official
[assessment rules article](https://learn.microsoft.com/en-us/data-migration/sql-server/database/assessment-rules?view=azuresql):

- Azure Migrate project + discover SQL Server instances (download appliance).
- Appliance registration on the VM, source connect `localhost` (Windows auth) + database discovery.
- Azure SQL Database assessment: readiness findings, SKU recommendation, monthly cost.

## Deprecated / superseded images

The earlier `c1-step-02-create-resource.png` … `c1-step-39-dms-create.png` set was captured from a
**different, heavier deployment** (`rg-sqlhack-microhack-2026`: 2 SQL VMs + SQL MI + Azure Migrate
appliance + Storage). They are **not referenced** by the lean `solution-01.md` and can be ignored or
removed.
