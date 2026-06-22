# Cost Model

## Per-resource rates (approximate, East US, 2026)

| Resource | SKU | Pay-as-you-go rate | Notes |
| --- | --- | --- | --- |
| SQL VM | Standard_D4s_v5 | ~$0.19/hour | Per team |
| JumpBox | Standard_D2s_v5 | ~$0.096/hour | Per team |
| Azure Bastion | Basic SKU | ~$0.19/hour + $0.01/GB | Shared |
| SQL MI | GP_Gen5_4vCores | ~$1.68/hour | Shared, opt-in |
| Storage Account | LRS, Standard | ~$0.02/GB/month | Shared |
| Log Analytics | PerGB2018 | ~$2.30/GB | First 5 GB free |
| Defender for SQL | Standard | ~$15/server/month | Opt-in |
| Public IP | Basic | ~$0.004/hour | For Bastion |

## Session cost scenarios

| Scenario | Duration | Teams | SQL MI | Estimated cost |
| --- | --- | --- | --- | --- |
| Quick test | 2 hours | 1 | No | ~$1-2 |
| Single-day workshop | 8 hours | 5 | No | ~$20-30 |
| Single-day workshop | 8 hours | 5 | Yes | ~$35-50 |
| Full-day with MI | 10 hours | 10 | Yes | ~$60-90 |

## Cost controls in this lab

- Auto-shutdown is configured at 19:00 UTC by default. Set -AutoShutdownTime to adjust.
- SQL MI is opt-in (-DeploySQLMI:$false by default) due to its 4-6 hour provisioning time and higher cost.
- Defender for SQL is opt-in to avoid unexpected ~$15/server/month charges.
- cleanup.ps1 deletes the entire resource group, stopping all charges immediately.

## Budget alerts (Bicep path only)

When deploying with -UseBicep, budget alerts are configured automatically:

- 50% threshold: informational email
- 75% threshold: warning email
- 90% threshold: warning email
- 100% threshold: alert email

Set -BudgetAmount and -BudgetContactEmail in deploy.ps1 to configure.
