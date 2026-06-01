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
