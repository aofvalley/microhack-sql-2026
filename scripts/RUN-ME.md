# Quick start — Deploy the lab

Single-user deployment validated against tenant
`0666b2b3-e005-4661-a4f3-ea42b8cc1257` / subscription
`79f0b936-0c80-4ecd-98a0-28160f412d14` on 2026-05-27. Repeat the steps below
with your own subscription/tenant.

## 1. Login

```powershell
az logout
az login --tenant <your-tenant-id> --use-device-code
az account set --subscription <your-subscription-id>
az account show   # confirm signed-in user
```

## 2. Deploy (single user, ~12 min)

```powershell
cd .\scripts
.\deploy.ps1 -SubscriptionId <your-sub> -TenantId <your-tenant>
```

Defaults: `TeamCount = 1`, `Location = westeurope`,
`ResourceGroup = rg-sqlhack-microhack-2026`, no SQL MI, auto-shutdown 19:00 UTC.
Override with `-TeamCount N` for a multi-team workshop.

The script is idempotent — safe to re-run after a partial failure.

## 3. Outputs

After a successful run, `scripts/out/` will contain:

| File | Use |
|------|-----|
| `team-credentials.csv` | SQL + VM admin credentials (DO NOT commit; `out/` is gitignored) |
| `connection-guide.md` | Bastion URL + login instructions |
| `deploy-<timestamp>.log` | Full transcript |

## 4. Portal captures

`Images/` already contains 17 reference screenshots taken against the validated
deployment. See `Images/README.md` for the per-step status (which are captured
vs. manual).

## 5. Tear down

```powershell
.\cleanup.ps1 -ResourceGroup rg-sqlhack-microhack-2026
# or, equivalently:
az group delete -n rg-sqlhack-microhack-2026 --yes --no-wait
```
