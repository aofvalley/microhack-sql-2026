# Challenge 1 — Image capture status

Screenshots were captured from a real lab deployment (resource group `rg-sqlhack-microhack-2026`)
with 2 SQL VMs (team-01) + JumpBox + Bastion + Storage. Some steps require manual capture
after running `scripts/deploy.ps1`.

## Captured (portal wizard flow)

| Step | File | What it shows |
|------|------|---------------|
| 02 | `c1-step-02-create-resource.png` | Marketplace > Create a resource |
| 03 | `c1-step-03-marketplace-sql-server-image.png` | Free SQL Server License: SQL 2019 on WS2019 (search result) |
| 04 | `c1-step-04-vm-basics.png` | VM wizard — Basics |
| 05 | `c1-step-05-vm-networking.png` | VM wizard — Networking |
| 07 | `c1-step-07-vm-review.png` | VM wizard — Review + create |
| 08 | `c1-step-08-bastion-connect.png` | Bastion connect blade |
| 18 | `c1-step-18-azure-migrate.png` | Azure Migrate — Get started |
| 19 | `c1-step-19-create-project.png` | Azure Migrate — Create project blade |
| 31 | `c1-step-31-sqlmi-basics.png` | SQL MI wizard — Basics |
| 32 | `c1-step-32-sqlmi-networking.png` | SQL MI wizard — Networking |
| 33 | `c1-step-33-sqlmi-security.png` | SQL MI wizard — Security |
| 34 | `c1-step-34-sqlmi-additional.png` | SQL MI wizard — Additional settings |
| 35 | `c1-step-35-sqlmi-review.png` | SQL MI wizard — Review + create |
| 36 | `c1-step-36-storage-create.png` | Storage account — Create wizard (Basics) |
| 37 | `c1-step-37-storage-container-backups.png` | Containers list — `backups` container |
| 38 | `c1-step-38-generate-sas.png` | Generate SAS dialog |
| 39 | `c1-step-39-dms-create.png` | Database Migration Service — Select scenario |

## Skipped

- **step-06** SQL Server settings tab — not present in current marketplace image; configured inside the VM instead.

## Manual — capture after `scripts/deploy.ps1`

Requires deployed resources:

- **step-01** Architecture diagram.
- **step-13** RDP to IaaS VM + Windows login.
- **step-20..23** Azure Migrate Discovery & Assessment.
- **step-41..43** DMS — Self-hosted Integration Runtime registration.
- **step-68** Post-migration validation.

## Manual — inside Windows VM (RDP)

Not accessible via automation (Windows session):

- **step-09..17** SQL Server in-VM configuration (SSCM, TCP, firewall, SSMS, database restore).
- **step-65..67** Post-migration validation from inside the VM.

## Manual — SSMS / VS Code (local client)

- **step-44..51** Path A (DMS) — Source assessment, MI target, mapping, runtime, run.
- **step-52..59** Path B (Managed Instance Link) — SSMS connection to SQL MI + Link wizard.
- **step-60..64** VS Code MSSQL extension — connection profile, query, deploy, schema compare.

## Summary

- **17/68** captured via automation (wizard + Bastion + Storage + SAS).
- **~28** require manual action (in-VM, SSMS, VS Code).
- **~9** require additional deployment (Azure Migrate appliance, DMS service).
- **1** skipped (step-06).
