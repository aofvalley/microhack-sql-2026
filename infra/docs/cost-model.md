# Cost model

> **Pricing warning:** Azure prices vary by region, offer, reservation, currency, and date. The
> estimates below are planning examples only. Always confirm with the Azure Pricing Calculator for
> the target region before deploying.

The default deployment is sized for **30 students**. The largest cost and time driver is Azure SQL Managed Instance. Deploying 30 SQL MIs is very expensive.

## Example hourly estimates per student

Illustrative estimates for West Europe-style pay-as-you-go planning:

| Resource | Quantity per student | Example hourly estimate | Notes |
| --- | ---: | ---: | --- |
| Source VM compute, `Standard_D4s_v5` | 1 | `$0.20-$0.30/hr` | VM can be auto-shutdown at `1900` UTC. SQL Server Developer edition does not add production SQL licensing cost. |
| VM OS/data disks | 1 set | `$0.02-$0.08/hr` | Depends on disk type and size. Continues while VM is stopped unless disks are deleted. |
| Public IPs | 1+ | `$0.005-$0.02/hr` | Depends on SKU and allocation. |
| Azure Bastion | 1 | `$0.15-$0.25/hr` | Per-student Bastion improves isolation but adds steady cost. |
| Azure SQL logical server | 1 | `$0/hr` | Logical server itself has no compute charge; databases created by students may add cost. |
| Azure SQL Database created by student | 0 initially | varies | No databases are pre-created by this infrastructure. |
| Azure SQL Managed Instance, GP_Gen5 4 vCores | 1 when `deploySqlMi=true` | `$0.80-$1.20/hr` plus storage | Slow to deploy and the dominant cost driver. |
| Log Analytics workspace | 1 | `~$0/hr` idle | PerGB2018 pay-as-you-go ingestion (first 5 GB/month free); negligible for lab telemetry volumes. |
| Storage, monitoring, bandwidth | varies | `$0.02-$0.10/hr` | Depends on usage. |

Planning shorthand:

- Without SQL MI: about **`$0.40-$0.75 per student-hour`**.
- With SQL MI: about **`$1.20-$2.00 per student-hour`**.

## Sample totals

| Students | Without SQL MI | With SQL MI | 8-hour lab without MI | 8-hour lab with MI | 24-hour run with MI |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `$0.40-$0.75/hr` | `$1.20-$2.00/hr` | `$3.20-$6.00` | `$9.60-$16.00` | `$28.80-$48.00` |
| 5 | `$2.00-$3.75/hr` | `$6.00-$10.00/hr` | `$16.00-$30.00` | `$48.00-$80.00` | `$144.00-$240.00` |
| 30 | `$12.00-$22.50/hr` | `$36.00-$60.00/hr` | `$96.00-$180.00` | `$288.00-$480.00` | `$864.00-$1,440.00` |

## SQL MI cost warning for 30 students

Each student receives one Azure SQL Managed Instance when `deploySqlMi=true`.

```text
30 students x 1 SQL MI each = 30 SQL Managed Instances
30 SQL MIs x ~$0.80-$1.20/hr = ~$24-$36/hr for SQL MI compute alone
24 hours x ~$24-$36/hr = ~$576-$864 for SQL MI compute alone
```

That does **not** include VMs, Bastion, storage, public IPs, student-created Azure SQL databases, monitoring, or bandwidth. If the environments remain deployed for a weekend, costs can grow quickly.

## Provisioning time considerations

| Component | Typical planning note |
| --- | --- |
| Resource groups, VNets, public IPs, SQL logical servers | Usually minutes. |
| Source VM and Custom Script Extension | VM deployment plus setup time; database restore and tooling install can take additional time. |
| Azure Bastion | Usually minutes, but deploys per student. |
| Azure SQL Managed Instance | Plan for **3-6 hours**. This can dominate total deployment time. |

## Cost-control recommendations

1. **Use `deploySqlMi=false` until needed.** Deploy SQL MI only for cohorts that will run Challenge 3.
2. **Keep `autoShutdownTime=1900` UTC.** This reduces VM compute spend after lab hours.
3. **Tear down promptly.** Delete student resource groups after the lab, especially when SQL MI was deployed.
4. **Deploy only the required capacity.** The default is 30 students, but use a smaller `userCount` for pilot runs.
5. **Use `startUserIndex` for batches.** Deploy a small validation batch first, then add more students if needed.
6. **Choose the region deliberately.** Confirm service availability, quota, and price in the selected `location`.
7. **Monitor quotas before deployment.** SQL MI and vCPU quota can block large cohorts.
8. **Avoid leaving student-created databases running.** Azure SQL databases created during Challenge 2 may add cost.

## Teardown expectation

Use `scripts\cleanup.ps1` or delete the per-student resource groups when the lab is complete.
Because the design uses one RG per student, teardown is simple and can be performed per failed
environment or for the full cohort.
