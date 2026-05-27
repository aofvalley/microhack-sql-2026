# Challenge 1 — Image capture status

Capturado con Playwright MCP en portal `admin@MngEnvMCAP872561.onmicrosoft.com` (tenant `0666b2b3-e005-4661-a4f3-ea42b8cc1257`). Despliegue real completado: RG `rg-sqlhack-microhack-2026` con 2 SQL VMs (team-01) + JumpBox + Bastion + Storage `sqlhacksafklplm`. Credenciales en `scripts/out/team-credentials.csv`.

## ✅ Capturadas (wizard de portal, estructura)

| Step | Archivo | Qué muestra |
|------|---------|-------------|
| 02 | `c1-step-02-create-resource.png` | Marketplace > Create a resource |
| 03 | `c1-step-03-marketplace-sql-server-image.png` | Free SQL Server License: SQL 2019 on Windows Server 2019 (resultado búsqueda) |
| 04 | `c1-step-04-vm-basics.png` | VM wizard — Basics |
| 05 | `c1-step-05-vm-networking.png` | VM wizard — Networking |
| 07 | `c1-step-07-vm-review.png` | VM wizard — Review + create (con validaciones) |
| 08 | `c1-step-08-bastion-connect.png` | Bastion connect blade (VM `sqlhack-team-01`) |
| 18 | `c1-step-18-azure-migrate.png` | Azure Migrate — Get started |
| 19 | `c1-step-19-create-project.png` | Azure Migrate — Create project blade |
| 31 | `c1-step-31-sqlmi-basics.png` | SQL MI wizard — Basics |
| 32 | `c1-step-32-sqlmi-networking.png` | SQL MI wizard — Networking |
| 33 | `c1-step-33-sqlmi-security.png` | SQL MI wizard — Security |
| 34 | `c1-step-34-sqlmi-additional.png` | SQL MI wizard — Additional settings |
| 35 | `c1-step-35-sqlmi-review.png` | SQL MI wizard — Review + create |
| 36 | `c1-step-36-storage-create.png` | Storage account — Create wizard (Basics) |
| 37 | `c1-step-37-storage-container-backups.png` | Containers list — `backups` creado en `sqlhacksafklplm` |
| 38 | `c1-step-38-generate-sas.png` | Generate SAS dialog (User delegation key, Read) |
| 39 | `c1-step-39-dms-create.png` | Database Migration Service — Select scenario & DMS |

## ⏭️ Skipped (no aplica)

- **step-06** "SQL Server settings" tab — la imagen de marketplace `Free SQL Server License: SQL 2019 on Windows Server 2019` NO tiene esa pestaña en el wizard actual (cambio del marketplace). Se debe configurar SQL ya dentro de la VM.

## ✋ Manual — capturar tras `scripts/deploy.ps1`

Requieren recursos desplegados:

- **step-01** Diagrama de arquitectura del challenge (Mermaid/Visio).
- **step-13** RDP a VM IaaS + login Windows.
- **step-20..23** Azure Migrate Discovery & Assessment (requiere proyecto Azure Migrate + appliance).
- **step-41..43** DMS — Self-hosted Integration Runtime registration (requiere DMS service desplegado).
- **step-68** Validación final post-migración.

## ✋ Manual — dentro de la VM Windows (RDP)

No accesibles por Playwright (sesión Windows interna):

- **step-09..17** Configuración SQL Server dentro de la VM (SSCM, TCP, firewall, SSMS local conectado a la VM SQL, bases de datos restauradas).
- **step-65..67** Validación post-migración desde dentro de la VM.

## ✋ Manual — SSMS / VS Code (cliente local)

- **step-44..51** Path A (DMS) — Source assessment, MI target, mapping, runtime, run.
- **step-52..59** Path B (Managed Instance Link) — SSMS connection a SQL MI + Link wizard.
- **step-60..64** VS Code MSSQL extension — connection profile, query, deploy, schema compare.

## Resumen

- **17/68** capturadas por automation (wizard + Bastion + Storage backups + SAS).
- **~28** requieren acción manual (in-VM, SSMS, VS Code).
- **~9** requieren despliegue adicional (Azure Migrate appliance, DMS service).
- **1** descartada (step-06).
