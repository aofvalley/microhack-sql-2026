# Solution 4 — Monitoring and Performance on Azure SQL Managed Instance (2026 edition)

[Previous Solution](../challenge-03/solution-03.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-05/solution-05.md)

## What changed since the original

The core monitoring flow from the original SQL Modernization MicroHack still applies: generate pressure on the migrated workload, identify the expensive query or stored procedure, validate the symptom in the Azure portal, and use Log Analytics to correlate resource pressure with waits, blocking, errors, and Query Store telemetry. The 2026 edition keeps Azure SQL Managed Instance (MI) as the target service and updates the monitoring path to emphasize **Azure Monitor for SQL**, **Diagnostic settings to Log Analytics**, **Query Store on Managed Instance**, and **Intelligent Insights signals** exposed through diagnostic categories such as `SQLInsights`, `QueryStoreRuntimeStatistics`, `QueryStoreWaitStatistics`, `Errors`, `Timeouts`, `Blocks`, and `Deadlocks`.

For teams that want a richer fleet view, Microsoft is also introducing **Database Watcher** as a preview-era monitoring experience for Azure SQL estates. Treat it as an optional enhancement for this lab: the mandatory path remains SQL MI diagnostics → Log Analytics workspace → KQL queries → Query Store/DMV analysis. Resource names continue from Solution 1, including `rg-microhack-sql-2026`, `sqlmi-microhack-2026`, and the Log Analytics workspace `la-microhack-sql`.

> **Lab scenario:** Users report that the migrated CRM workload is slow after recent stored procedure changes. You will create monitoring signal, find the highest CPU consumers, inspect portal metrics and Log Analytics records, then apply Query Store and tuning features to validate the fix.

## Step 1 — Enable diagnostic settings on SQL MI

Open the Azure portal and navigate to **SQL managed instances** → `sqlmi-microhack-2026` → **Monitoring** → **Diagnostic settings**. Create a diagnostic setting named `diag-sqlmi-to-la` and send logs to the Log Analytics workspace `la-microhack-sql` in `rg-microhack-sql-2026`.

![SQL MI diagnostic settings blade](../../Images/c2-step-01-sql-mi-diagnostic-settings-blade.png)

Enable the following log categories. Some categories are instance-scoped and some are database-scoped; enable all that are available in your tenant/region for the Managed Instance and migrated database:

- `SQLInsights`
- `ResourceUsageStats`
- `SQLSecurityAuditEvents`
- `Errors`
- `Timeouts`
- `Blocks`
- `Deadlocks`
- `AutomaticTuning`
- `QueryStoreRuntimeStatistics`
- `QueryStoreWaitStatistics`
- `DevOpsOperationsAudit`

Also enable **AllMetrics** if the option is shown. Save the diagnostic setting and wait 5-10 minutes before expecting events in Log Analytics.

![Diagnostic categories selected](../../Images/c2-step-02-diagnostic-categories-selected.png)

If you prefer Azure CLI, use the same resource names from Solution 1:

```bash
az monitor diagnostic-settings create \
  --name diag-sqlmi-to-la \
  --resource $(az sql mi show \
      --resource-group rg-microhack-sql-2026 \
      --name sqlmi-microhack-2026 \
      --query id -o tsv) \
  --workspace $(az monitor log-analytics workspace show \
      --resource-group rg-microhack-sql-2026 \
      --workspace-name la-microhack-sql \
      --query id -o tsv) \
  --logs '[
    {"category":"SQLInsights","enabled":true},
    {"category":"ResourceUsageStats","enabled":true},
    {"category":"SQLSecurityAuditEvents","enabled":true},
    {"category":"Errors","enabled":true},
    {"category":"Timeouts","enabled":true},
    {"category":"Blocks","enabled":true},
    {"category":"Deadlocks","enabled":true},
    {"category":"AutomaticTuning","enabled":true},
    {"category":"QueryStoreRuntimeStatistics","enabled":true},
    {"category":"QueryStoreWaitStatistics","enabled":true},
    {"category":"DevOpsOperationsAudit","enabled":true}
  ]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

![Log Analytics workspace destination](../../Images/c2-step-03-log-analytics-workspace-destination.png)

## Step 2 — Generate workload pressure

Connect to the migrated database, for example `AdventureWorks2019` or `TenantCRM`, from SQL Server Management Studio (SSMS) or VS Code with the MSSQL extension. Use the SQL login provided for the lab and the fully qualified MI host name from the portal overview.

![SSMS connect to managed instance](../../Images/c2-step-04-ssms-connect-managed-instance.png)

Run a synthetic workload for 10-15 minutes so the portal, Query Store, DMVs, and Log Analytics all have enough signal. The following script deliberately creates CPU pressure, logical reads, a cursor loop, and a missing-index-style scan. If your repo includes `scripts/load-test.sql`, you can run that script instead and keep this section as the explanation of what the workload is doing.

```sql
USE AdventureWorks2019;
GO

CREATE OR ALTER PROCEDURE dbo.usp_MicroHackCpuPressure
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (75000)
        h.SalesOrderID,
        h.CustomerID,
        h.OrderDate,
        SUM(d.LineTotal) OVER (PARTITION BY h.CustomerID ORDER BY h.OrderDate) AS running_total,
        AVG(d.LineTotal) OVER (PARTITION BY h.TerritoryID) AS avg_territory_line_total
    FROM Sales.SalesOrderHeader AS h
    CROSS JOIN Sales.SalesOrderDetail AS d
    WHERE h.OrderDate >= '2013-01-01'
    OPTION (MAXDOP 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_MicroHackCursorPressure
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @salesOrderId int;
    DECLARE order_cursor CURSOR FAST_FORWARD FOR
        SELECT TOP (5000) SalesOrderID
        FROM Sales.SalesOrderHeader
        ORDER BY OrderDate DESC;

    OPEN order_cursor;
    FETCH NEXT FROM order_cursor INTO @salesOrderId;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT COUNT_BIG(*)
        FROM Sales.SalesOrderDetail AS d
        WHERE d.SalesOrderID >= @salesOrderId;

        FETCH NEXT FROM order_cursor INTO @salesOrderId;
    END

    CLOSE order_cursor;
    DEALLOCATE order_cursor;
END;
GO

-- Deliberate missing-index scan pattern: filter on a non-covering expression.
SELECT TOP (1000)
    p.BusinessEntityID,
    p.FirstName,
    p.LastName
FROM Person.Person AS p
WHERE LEFT(p.LastName, 2) = 'Sm'
ORDER BY p.ModifiedDate DESC;
GO

-- Run from 2-3 query windows to create pressure.
DECLARE @i int = 0;
WHILE @i < 40
BEGIN
    EXEC dbo.usp_MicroHackCpuPressure;
    EXEC dbo.usp_MicroHackCursorPressure;
    WAITFOR DELAY '00:00:03';
    SET @i += 1;
END;
GO
```

![VS Code MSSQL workload execution](../../Images/c2-step-05-vscode-mssql-workload-execution.png)

## Step 3 — Identify the top CPU consumers via DMVs

DMVs help you separate *running* issues from *waiting* issues. Running queries have CPU and are taking time to complete. Waiting queries are blocked on CPU, IO, locks, memory, log writes, or another resource. Start with aggregate CPU consumers since the lab workload intentionally creates CPU pressure.

Run this query in the migrated database:

```sql
SELECT TOP (20)
    DB_NAME(st.dbid) AS database_name,
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_ms,
    (qs.total_worker_time / NULLIF(qs.execution_count, 0)) / 1000 AS avg_cpu_ms,
    qs.total_elapsed_time / 1000 AS total_elapsed_ms,
    qs.total_logical_reads,
    qs.total_logical_writes,
    qs.creation_time,
    qs.last_execution_time,
    SUBSTRING(
        st.text,
        (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1
    ) AS statement_text,
    qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.dbid = DB_ID()
ORDER BY qs.total_worker_time DESC;
```

![Top CPU DMV query results](../../Images/c2-step-06-top-cpu-dmv-query-results.png)

Open the XML execution plan for the top row. Look for scans, high estimated rows, warning icons, spills, missing index suggestions, repeated cursor activity, or expensive window aggregates. In this lab you should see the synthetic procedures near the top after several executions.

![Execution plan for top consumer](../../Images/c2-step-07-execution-plan-top-consumer.png)

For active requests, use this companion query:

```sql
SELECT
    r.session_id,
    r.status,
    r.command,
    r.cpu_time,
    r.total_elapsed_time,
    r.logical_reads,
    r.wait_type,
    r.blocking_session_id,
    DB_NAME(r.database_id) AS database_name,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1
    ) AS running_statement
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID
ORDER BY r.cpu_time DESC;
```

## Step 4 — Review Performance Overview in the Portal

Return to the Azure portal → **SQL managed instances** → `sqlmi-microhack-2026` → **Overview**. Review the built-in CPU chart for the last hour, then switch to 24 hours and 7 days. Confirm whether the workload changed the CPU pattern.

![SQL MI overview CPU chart](../../Images/c2-step-08-sql-mi-overview-cpu-chart.png)

Open **Monitoring** → **Metrics**. Set scope to `sqlmi-microhack-2026`, metric namespace to SQL managed instance metrics, and add:

- `CPU percentage`
- `Data IO percentage`
- `Log IO percentage`
- `Storage space used`
- `Sessions count` or `Workers percentage` if available

![Metrics blade CPU and IO](../../Images/c2-step-09-metrics-blade-cpu-and-io.png)

Under **Intelligent Performance**, review available recommendations and Intelligent Insights. The objective is not to accept every recommendation immediately; the objective is to correlate the portal signal with the DMV and Query Store evidence.

![Intelligent Performance blade](../../Images/c2-step-10-intelligent-performance-blade.png)

## Step 5 — Query Log Analytics with KQL

Open the Log Analytics workspace `la-microhack-sql` → **Logs**. The diagnostic records land in the `AzureDiagnostics` table. In many workspaces string and numeric diagnostic fields have suffixes such as `_s`, `_d`, `_g`, and `_b`; use `project`/`getschema` if your column names differ.

![Log Analytics Logs query editor](../../Images/c2-step-11-log-analytics-query-editor.png)

### Query 1 — CPU utilization over time

This query charts SQL MI CPU from the `ResourceUsageStats` category and validates whether the synthetic pressure is visible outside the database engine.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(6h)
| where Resource =~ "sqlmi-microhack-2026"
| where Category == "ResourceUsageStats"
| extend cpu_percent = todouble(avg_cpu_percent_s)
| summarize avg_cpu_percent = avg(cpu_percent), max_cpu_percent = max(cpu_percent) by bin(TimeGenerated, 5m)
| order by TimeGenerated asc
| render timechart
```

### Query 2 — Top long-running Query Store runtime records

This query uses `QueryStoreRuntimeStatistics` records to find queries with the highest duration or CPU reported through diagnostics.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == "QueryStoreRuntimeStatistics"
| extend database_name = coalesce(DatabaseName_s, database_name_s, Resource)
| extend query_id = tostring(query_id_d), plan_id = tostring(plan_id_d)
| extend avg_duration_ms = todouble(avg_duration_ms_d), max_duration_ms = todouble(max_duration_ms_d)
| extend avg_cpu_ms = todouble(avg_cpu_time_ms_d), execution_count = todouble(count_executions_d)
| summarize executions = sum(execution_count), avg_duration_ms = avg(avg_duration_ms), max_duration_ms = max(max_duration_ms), avg_cpu_ms = avg(avg_cpu_ms)
    by database_name, query_id, plan_id
| top 20 by max_duration_ms desc
```

### Query 3 — Blocking events

This query shows blocking diagnostics and helps determine whether slowness is caused by lock waits instead of pure CPU pressure.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == "Blocks"
| extend database_name = coalesce(DatabaseName_s, database_name_s, Resource)
| project TimeGenerated,
          database_name,
          blocked_process_report_s,
          session_id_d,
          blocking_session_id_d,
          wait_time_ms_d,
          statement_s
| order by TimeGenerated desc
```

### Query 4 — Deadlock reports

This query retrieves deadlock events so you can inspect the XML/report payload and identify the victim, owner, waiter, and locked resources.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == "Deadlocks"
| extend database_name = coalesce(DatabaseName_s, database_name_s, Resource)
| project TimeGenerated,
          database_name,
          deadlock_xml = coalesce(deadlock_xml_s, report_s, event_s, statement_s),
          client_app_name_s,
          host_name_s,
          server_principal_name_s
| order by TimeGenerated desc
```

### Query 5 — Query Store wait stats trend

This query trends waits by category so you can distinguish CPU, IO, lock, memory, and log pressure over time.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == "QueryStoreWaitStatistics"
| extend database_name = coalesce(DatabaseName_s, database_name_s, Resource)
| extend wait_category = coalesce(wait_category_s, wait_category_desc_s, "unknown")
| extend total_wait_ms = todouble(total_query_wait_time_ms_d)
| summarize total_wait_ms = sum(total_wait_ms) by database_name, wait_category, bin(TimeGenerated, 15m)
| order by TimeGenerated asc
| render timechart
```

![KQL CPU utilization chart](../../Images/c2-step-12-kql-cpu-utilization-chart.png)

![KQL wait stats trend chart](../../Images/c2-step-13-kql-wait-stats-trend-chart.png)

## Step 6 — Use Query Store for regression analysis

Query Store is supported on Azure SQL Managed Instance and is the best built-in feature for query regression analysis because it persists query text, runtime statistics, waits, and plans over time.

Enable Query Store on the migrated database if it is not already enabled:

```sql
ALTER DATABASE AdventureWorks2019 SET QUERY_STORE = ON;
GO

ALTER DATABASE AdventureWorks2019 SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    WAIT_STATS_CAPTURE_MODE = ON,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 15,
    MAX_STORAGE_SIZE_MB = 1024
);
GO
```

In SSMS, expand the migrated database → **Query Store**. Open **Top Resource Consuming Queries**, **Regressed Queries**, and **Queries With Forced Plans**. Run the workload again and refresh the reports.

![SSMS Query Store reports node](../../Images/c2-step-14-ssms-query-store-reports-node.png)

When you identify a regressed query, compare the previous plan and current plan. If a known good plan is available, force it from the SSMS report or use T-SQL:

```sql
-- Replace with the query_id and plan_id from Query Store reports.
EXEC sys.sp_query_store_force_plan
    @query_id = 42,
    @plan_id = 7;
GO

SELECT
    qsq.query_id,
    qsp.plan_id,
    qsp.is_forced_plan,
    qsp.force_failure_count,
    qsp.last_force_failure_reason_desc,
    qsqt.query_sql_text
FROM sys.query_store_query AS qsq
JOIN sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
JOIN sys.query_store_query_text AS qsqt
    ON qsq.query_text_id = qsqt.query_text_id
WHERE qsp.is_forced_plan = 1;
```

![Query Store regressed query plan comparison](../../Images/c2-step-15-query-store-regressed-query-plan-comparison.png)

## Step 7 — Configure Automatic Tuning + alerts

Automatic tuning can help stabilize workloads by applying or recommending plan and index changes. In the Azure portal, open `sqlmi-microhack-2026` → **Intelligent Performance** → **Automatic tuning**. Enable or inherit the following options according to the lab policy:

- `FORCE_LAST_GOOD_PLAN`
- `CREATE_INDEX`
- `DROP_INDEX`

![Automatic tuning options](../../Images/c2-step-16-automatic-tuning-options.png)

You can also use T-SQL at the database level where applicable:

```sql
ALTER DATABASE AdventureWorks2019 SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
GO

SELECT name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;
```

Next, create an Azure Monitor alert. Open **Monitoring** → **Alerts** → **Create** → **Alert rule**. Use scope `sqlmi-microhack-2026`, signal **CPU percentage**, threshold **Greater than 80**, aggregation **Average**, evaluation frequency **5 minutes**, and lookback/window **10 minutes**.

![Create alert rule condition](../../Images/c2-step-17-create-alert-rule-condition.png)

Create or select an action group named `ag-microhack-sql-ops`. Add an email receiver for the lab operator and a Teams webhook receiver if your tenant allows incoming webhooks or workflow-based Teams notifications. Name the alert `sqlmi-high-cpu-80pct-10m` and set severity to 2.

![Alert action group email teams](../../Images/c2-step-18-alert-action-group-email-teams.png)

## Step 8 — Validate fixes

Apply the chosen fix: force the known good Query Store plan, add the missing index if justified, or reduce the synthetic workload. Then re-run the same load test from Step 2 and compare the before/after evidence.

Suggested validation checklist:

1. The DMV query from Step 3 no longer shows the same statement dominating total CPU.
2. Query Store shows the selected plan as forced and `force_failure_count = 0`.
3. Azure portal metrics show CPU returning below the alert threshold.
4. The Log Analytics CPU timechart stabilizes after the fix window.
5. The high CPU alert does not fire again during the validation run.

![Query Store forced plan validation](../../Images/c2-step-19-query-store-forced-plan-validation.png)

![Resolved metrics CPU stabilized](../../Images/c2-step-20-resolved-metrics-cpu-stabilized.png)

![Alert rule healthy state](../../Images/c2-step-21-alert-rule-healthy-state.png)

At this point you have used the same layers you would use in a production incident: engine-level DMVs, persisted Query Store telemetry, Azure portal metrics, diagnostic logs in Log Analytics, and Azure Monitor alerting. In a real engagement, document the root cause, the evidence, the remediation, and the post-fix baseline.

## Learning resources

- [Monitor Azure SQL Managed Instance with Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/monitoring-sql-managed-instance-azure-monitor?view=azuresql)
- [Azure SQL monitoring with Azure Monitor SQL insights](https://learn.microsoft.com/en-us/azure/azure-monitor/insights/azure-sql?tabs=portal)
- [Monitor Azure SQL Database and Azure SQL Managed Instance using database watcher](https://learn.microsoft.com/en-us/azure/azure-sql/database-watcher-overview?view=azuresql)
- [Intelligent Insights performance diagnostics](https://learn.microsoft.com/en-us/azure/azure-sql/database/intelligent-insights-overview?view=azuresql)
- [Monitor performance by using the Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store?view=sql-server-ver17)
- [Query Store usage scenarios](https://learn.microsoft.com/en-us/sql/relational-databases/performance/query-store-usage-scenarios?view=sql-server-ver17)
- [Automatic tuning in Azure SQL Database and Azure SQL Managed Instance](https://learn.microsoft.com/en-us/azure/azure-sql/database/automatic-tuning-overview?view=azuresql)
- [Kusto Query Language reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [AzureDiagnostics table reference](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azurediagnostics)

---

[Previous Solution](../challenge-03/solution-03.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-05/solution-05.md)
