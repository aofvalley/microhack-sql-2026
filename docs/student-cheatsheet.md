# Student Cheatsheet

## Connection strings

| Target | Connection string |
| --- | --- |
| SQL VM (from JumpBox via SSMS) | Server: `sqlhack-team-XX` (or IP); Auth: SQL Login `TEAM0X_admin` |
| SQL MI (public endpoint) | Server: `mi-name.public.hash.database.windows.net,3342`; Auth: SQL Login |
| SQL MI (private, from JumpBox) | Server: `mi-name.hash.database.windows.net`; Auth: SQL or Azure AD |

Your team's credentials are in `scripts/out/team-credentials.csv` (provided by facilitator).

## Migration paths comparison

| Path | Source compatibility | Online migration | Link persistence | 2026 recommendation |
| --- | --- | --- | --- | --- |
| DMS | SQL 2005+ | Yes (CDC) | No | Good for older sources |
| Managed Instance Link | SQL 2019+ (CU15+), 2022+ | Yes (AG-based) | Yes (can keep as DR) | **Recommended** |
| LRS (Log Replay) | SQL 2008+ | Yes (log shipping) | No | Good for offline/controlled |

## Challenge 1 — Key SQL commands

Check databases on source VM:

```sql
SELECT name, compatibility_level FROM sys.databases ORDER BY name;
SELECT @@VERSION;
```

## Challenge 2 — KQL queries for Log Analytics

CPU over time for SQL VM:

```kql
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize avg(CounterValue) by bin(TimeGenerated, 5m), Computer
| render timechart
```

Top queries by average duration (Query Store — run in SSMS against the database):

```sql
SELECT TOP 10 qt.query_sql_text, rs.avg_duration
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC;
```

## Challenge 2 — Invoke dirty workload

From the repo root on the JumpBox:

```powershell
.\scripts\sql\Invoke-DirtyWorkload.ps1 -TeamPrefix TEAM01 -SqlInstance sqlhack-team-01
```

## Challenge 3 — Security commands

Check TDE status on SQL MI:

```sql
SELECT db_name(database_id), encryption_state_desc
FROM sys.dm_database_encryption_keys;
```

## Challenge checklists

### Challenge 1

- [ ] Source assessment completed (no blockers found)
- [ ] SQL MI provisioned and reachable from JumpBox
- [ ] Storage account and `backups` container created
- [ ] Migration started via chosen path (DMS / MI Link / LRS)
- [ ] AdventureWorks2019 visible on SQL MI

### Challenge 2

- [ ] Query Store enabled and showing data
- [ ] Dirty workload executed
- [ ] Database Watcher connected to SQL MI
- [ ] At least one KQL query executed in Log Analytics

### Challenge 3

- [ ] Defender for SQL enabled and showing recommendations
- [ ] TDE status confirmed
- [ ] Auditing configured
- [ ] Azure AD authentication tested
