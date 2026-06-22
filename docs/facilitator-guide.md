# Facilitator Guide

## Pre-flight checklist

- [ ] Azure subscription with Owner or Contributor + UAA role confirmed
- [ ] Quota available: vCPUs (D-series), Public IPs (for Bastion), SQL MI vCores (if enabled)
- [ ] `deploy.ps1` dry-run completed: `deploy.ps1 -DryRun -TeamCount N`
- [ ] `users.csv` prepared from `scripts/users.csv.example` template
- [ ] Estimated cost reviewed against session budget (see `docs/cost-model.md`)
- [ ] `validate.ps1` green after deployment
- [ ] Auto-shutdown time confirmed for session timezone

## Timing guide

| Activity | Estimated time |
| --- | --- |
| Deployment (1-2 teams) | 20-35 min |
| Deployment (10 teams, parallel) | 45-60 min |
| Challenge 1 — Assessment & Migration | 60-90 min |
| Challenge 2 — Monitoring & Performance | 45-60 min |
| Challenge 3 — Security | 45-60 min |
| Cleanup | 5-10 min |
| **Total** | **~3-4 hours** |

## Cohort size guidance

| Size | Teams | SQL VMs | JumpBoxes | Notes |
| --- | --- | --- | --- | --- |
| Single | 1 | 1 | 1 | Self-paced, no coordination needed |
| Small | 2-5 | 2-5 | 2-5 | Standard workshop format |
| Medium | 6-15 | 6-15 | 6-15 | Consider parallel deploy |
| Large | 16-50 | 16-50 | 16-50 | Requires quota increase; pre-warm 48h |

## Per-challenge facilitator notes

### Challenge 1 — Assessment & Migration

- Three migration paths are presented: DMS, Managed Instance Link, LRS.
- **MI Link is the recommended 2026 path** for SQL 2019/2022 sources.
- DMS and LRS remain valid for SQL 2012/2014/2016.
- Common blocker: participants forget to start the SQL Server Agent before initiating MI Link.

### Challenge 2 — Monitoring & Performance

- `Invoke-DirtyWorkload.ps1` generates the workload needed for Query Store to populate.
- Database Watcher is in preview; some portal features may differ from screenshots.
- KQL queries in `docs/student-cheatsheet.md` are tested against the deployed Log Analytics workspace.

### Challenge 3 — Security

- Defender for SQL takes 5-10 min to show findings after enabling.
- TDE is on by default on SQL MI; walk participants through the key rotation flow.
- Azure AD authentication requires the lab tenant to have at least one non-guest user account.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Bastion cannot connect to VM | CSE still running (VM boot) | Wait 5 min and retry |
| SQL MI not reachable from JumpBox | MI provisioning not complete | MI takes 4-6 hours; deploy 24h before |
| `validate.ps1` fails on SQL login | CSE did not complete | Check CSE log in VM serial console |
| `deploy.ps1` exits on quota error | Insufficient vCPU quota | Request quota increase in Azure Portal |
| Auto-shutdown fired during lab | Timezone mismatch | Set `-AutoShutdownTime 2200` in deploy.ps1 |

## Cleanup

Run from repo root:

```powershell
.\scripts\cleanup.ps1 -ResourceGroupName rg-sqlhack-prefix
```

Verify: `az group show --name rg-sqlhack-prefix --query provisioningState`
