# Solution 4 — Monitoring and Performance on Azure SQL Managed Instance (2026 edition)

[Previous Solution](../challenge-03/solution-03.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-05/solution-05.md)

> **Lab scenario:** Users report that the migrated CRM workload is slow after recent stored procedure changes. You will create monitoring signal, find the highest CPU consumers, inspect portal metrics and Log Analytics records, then apply Query Store and tuning features to validate the fix.

> **Timing:** Allow 45–60 minutes for Steps 1–8. If your facilitator pre-deployed diagnostic settings during the initial deployment, verify they are configured in Step 1 and proceed to Step 2.

## Step 1 — Enable diagnostic settings on SQL MI

> **Note:** The deployment Bicep (`infra/modules/monitoring.bicep`) already provisions the Log Analytics workspace `log-<prefix>`. If your facilitator also pre-configured diagnostic settings on the SQL MI, verify the categories below are enabled and skip to Step 2.

SQL Managed Instance requires **two separate diagnostic settings**: one on the managed instance resource (instance-level telemetry) and one on each individual database (database-level telemetry). Open the Azure portal and navigate to **SQL managed instances** → `sqlmi-microhack-2026` → **Monitoring** → **Diagnostic settings**.

![SQL MI diagnostic settings blade](../../Images/c4-step-01-server-diag-settings.png)

**Instance-level diagnostic setting** — Create a setting named `diag-sqlmi-instance-to-la` on the managed instance resource. Enable:

- `Resource Usage Statistics`

**Database-level diagnostic setting** — Navigate to your migrated database (e.g., `AdventureWorks2019`) within the managed instance → **Monitoring** → **Diagnostic settings**. Create a setting named `diag-sqlmi-db-to-la`. Enable:

- `SQLInsights`
- `QueryStoreRuntimeStatistics`
- `QueryStoreWaitStatistics`
- `Errors`

![SQL MI database diagnostic settings blade](../../Images/c4-step-02-database-diag-settings.png)

Send both diagnostic settings to the Log Analytics workspace `la-microhack-sql` in `rg-microhack-sql-2026`. Save and wait 5-10 minutes before expecting events in Log Analytics.

> **Note:** Categories such as `Timeouts`, `Blocks`, `Deadlocks`, `DatabaseWaitStatistics`, and `AutomaticTuning` are available only on **Azure SQL Database** and do not apply to SQL Managed Instance. If you need blocking and deadlock data on SQL MI, use engine-level DMVs (e.g., `sys.dm_exec_requests`, `sys.dm_tran_locks`) or Extended Events instead.

![Diagnostic categories selected](../../Images/c4-step-03-database-diag-settings-cat-selected.png)

If you prefer Azure CLI, use the same resource names from Solution 1. Note that you need **two commands** — one for the instance and one for the database:

```bash
# Instance-level diagnostic setting (ResourceUsageStats + metrics)
az monitor diagnostic-settings create \
  --name diag-sqlmi-instance-to-la \
  --resource $(az sql mi show \
      --resource-group rg-microhack-sql-2026 \
      --name sqlmi-microhack-2026 \
      --query id -o tsv) \
  --workspace $(az monitor log-analytics workspace show \
      --resource-group rg-microhack-sql-2026 \
      --workspace-name la-microhack-sql \
      --query id -o tsv) \
  --logs '[
    {"category":"ResourceUsageStats","enabled":true}
  ]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# Database-level diagnostic setting (per migrated database)
az monitor diagnostic-settings create \
  --name diag-sqlmi-db-to-la \
  --resource $(az sql mi show \
      --resource-group rg-microhack-sql-2026 \
      --name sqlmi-microhack-2026 \
      --query id -o tsv)/databases/AdventureWorks2019 \
  --workspace $(az monitor log-analytics workspace show \
      --resource-group rg-microhack-sql-2026 \
      --workspace-name la-microhack-sql \
      --query id -o tsv) \
  --logs '[
    {"category":"SQLInsights","enabled":true},
    {"category":"QueryStoreRuntimeStatistics","enabled":true},
    {"category":"QueryStoreWaitStatistics","enabled":true},
    {"category":"Errors","enabled":true}
  ]'
```

![Log Analytics workspace destination](../../Images/c4-step-04-database-diag-settings-configured.png)

## Step 2 — Generate workload pressure

Connect to the migrated database `AdventureWorks2019`, from SQL Server Management Studio (SSMS). Use your AAD user and the fully qualified MI host name from the portal overview. Keep in mind we are connecting to the Public endpoint, so the connection is made via de 3342 port.

![SSMS connect to managed instance](../../Images/c4-step-05-connect-ssms-managed-instance.png)

![SSMS connect to managed instance](../../Images/c4-step-06-connect-ssms-managed-instance-2.png)

> **Multi-team deployments:** If your lab uses team-prefixed databases (e.g., `TEAM01_AdventureWorks2019`), replace every `AdventureWorks2019` reference in this walkthrough with your team-prefixed database name.

Run a synthetic workload for 10-15 minutes so the portal, Query Store, DMVs, and Log Analytics all have enough signal. The following script deliberately creates CPU pressure, logical reads, a cursor loop, and a missing-index-style scan.
(Do not wait for the script to finish as it will take a very long time)

```sql
USE AdventureWorks2019;
GO

CREATE OR ALTER PROCEDURE dbo.usp_MicroHackCpuPressure
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (3000000)
        h.SalesOrderID,
        h.CustomerID,
        h.OrderDate,
        SUM(d.LineTotal) OVER (PARTITION BY h.CustomerID ORDER BY h.OrderDate) AS running_total
        --,AVG(d.LineTotal) OVER (PARTITION BY h.TerritoryID) AS avg_territory_line_total
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
        SELECT TOP (100) SalesOrderID
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
WHILE @i < 10
BEGIN
    EXEC dbo.usp_MicroHackCpuPressure;
    EXEC dbo.usp_MicroHackCursorPressure;
    WAITFOR DELAY '00:00:03';
    SET @i += 1;
END;
GO
```

![VS Code MSSQL workload execution](../../Images/c4-step-07-ssms-query-execution.png)

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

![Top CPU DMV query results](../../Images/c4-step-08-cpu-dmv-query-results.png)

Open the XML execution plan for the top row. Look for scans, high estimated rows, warning icons, spills, missing index suggestions, repeated cursor activity, or expensive window aggregates. In this lab you should see the synthetic procedures near the top after several executions.

![Execution plan for top consumer](../../Images/c4-step-09-execution-plan.png)

### Snapshot server-wide wait stats

This quick query shows the top wait types across the entire instance, which you can compare with the per-query wait stats in Step 5 (KQL Query 5) and Step 6 (Query Store):

```sql
SELECT TOP (10)
    wait_type,
    wait_time_ms,
    signal_wait_time_ms,
    waiting_tasks_count
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE '%SLEEP%'
  AND wait_type NOT LIKE '%IDLE%'
  AND wait_type NOT LIKE '%QUEUE%'
  AND wait_type <> 'WAITFOR'
ORDER BY wait_time_ms DESC;
```
![Wait times](../../Images/c4-step-10-wait-times.png)

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

![Active requests](../../Images/c4-step-11-running-queries.png)

## Step 4 — Review Performance Overview in the Portal

Return to the Azure portal → **SQL managed instances** → `sqlmi-microhack-2026` → **Overview**. Review the built-in CPU chart for the last hour, then switch to 24 hours and 7 days. Confirm whether the workload changed the CPU pattern.

![SQL MI overview CPU chart](../../Images/c4-step4-SQLMI-CPU-chart.png)

Open **Monitoring** → **Metrics**. Set scope to `sqlmi-microhack-2026`, metric namespace to SQL managed instance metrics, and add:

- `Average CPU percentage`
- `IO bytes read` and/or `IO bytes written`
- `IO requests count`
- `Storage space used`
- `Virtual core count`

![Metrics blade CPU and IO](../../Images/c4-step4-SQLMI-Monitoring-Metrics.png)

Under **Logs**, review available recommendations and Intelligent Insights. The objective is not to accept every recommendation immediately; the objective is to correlate the portal signal with the DMV and Query Store evidence.

![Intelligent Insights](../../Images/c4-step4-SQLMI-Intelligent-Insights.png)

In **Logs** tab, in the right top corner try the new **Observability agent**, a temporary chat that can assist you analyze the metrics and logs.

![Observability agent](../../Images/c4-step4-SQLMI-Observability-Agent.png)

### Try these questions with the Observability agent

The agent has access to the same metrics, diagnostic logs, and resource health signals you just opened in the portal. Use it to **shortcut the manual KQL and DMV work** of Steps 3, 5 and 6 — then validate its answers against the queries you ran yourself. Ask the questions below in order; each one builds on the previous answer the same way a real incident investigation does.

> **Tip:** Keep each prompt **short and single-focus**. The agent is slow on compound questions ("when, how long, and peak…") because it runs a separate KQL query per intent. One question = one signal = a fast answer. Ask in order; each builds on the previous.

> **Tip:** The agent is a *temporary* chat — copy answers you want to keep before closing the blade.

1. **"Show CPU usage for the last hour."**
   - *Why ask:* Anchors the investigation to a concrete time window. Every later query (DMV, Log Analytics, Query Store) should target that window so you can compare apples to apples.

2. **"Is the current pressure CPU or IO?"**
   - *Why ask:* The Step 2 workload hits both. Knowing which dominates tells you whether to fix queries/indexes (CPU/IO) or scale vCores (capacity).

3. **"Top 5 CPU-consuming queries on `AdventureWorks2019` in the last hour."**
   - *Why ask:* The agent's version of the Step 3 DMV query. If `usp_MicroHackCpuPressure` / `usp_MicroHackCursorPressure` appear, your diagnostic settings from Step 1 are working end-to-end.

4. **"Top wait types on `AdventureWorks2019` right now."**
   - *Why ask:* Waits explain *why* a query is slow, not just *that* it is. Natural-language equivalent of Step 5 Query 5 and the `sys.dm_os_wait_stats` snapshot in Step 3.

5. **"Any missing-index recommendations for `AdventureWorks2019`?"**
   - *Why ask:* Catches the non-SARGable `LEFT(LastName, 2) = 'Sm'` scan and the CROSS JOIN from Step 2. Missing-index hints are the highest-signal recommendations and map directly to the Step 8 remediation.

6. **"Give me a KQL query to chart CPU per database for the last 6 hours."**
   - *Why ask:* Turns the agent into a launchpad for Step 5 — leaves you with a ready-to-paste KQL query instead of writing one from scratch.

> **Lab discipline:** Always cross-check the agent's answers against the DMV results from Step 3 and the Query Store reports from Step 6. 

## Step 5 — Query Log Analytics with KQL

Open the Log Analytics workspace `la-microhack-sql` → **Logs**. The diagnostic records land in the `AzureDiagnostics` table. In many workspaces string and numeric diagnostic fields have suffixes such as `_s`, `_d`, `_g`, and `_b`; use `project`/`getschema` if your column names differ.

> **Tip:** If you are unsure which columns exist for a given category, run this schema discovery query first:
>
> ```kusto
> AzureDiagnostics
> | where TimeGenerated > ago(1h)
> | where Category == "ResourceUsageStats"
> | getschema
> ```
>
> Replace the `Category` value with any category from Step 1 to inspect its columns.

![Log Analytics Logs query editor](../../Images/c4-step4-SQLMI-LogAnalyticsQueryEditor.png)

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
| extend database_name = coalesce(DatabaseName_s, Resource)
| extend query_id = tostring(query_id_d), plan_id = tostring(plan_id_d)
| extend duration_us = todouble(duration_d), max_duration_us = todouble(max_duration_d)
| extend cpu_time_us = todouble(cpu_time_d), execution_count = todouble(count_executions_d)
| summarize executions = sum(execution_count),
    avg_duration_ms = avg(duration_us / execution_count) / 1000,
    max_duration_ms = max(max_duration_us) / 1000,
    avg_cpu_ms = avg(cpu_time_us / execution_count) / 1000
    by database_name, query_id, plan_id
| top 20 by max_duration_ms desc
```

> **Tip:** The `QueryStoreRuntimeStatistics` fields `duration_d`, `cpu_time_d`, etc. store values in **microseconds**. Divide by 1,000 to convert to milliseconds. Use `getschema` (see the Tip above) to discover the exact column names in your workspace.

### Query 3 — Detect blocking via DMVs (SQL MI)

Run the following T-SQL directly against the managed instance to check for current blocking chains:

```sql
-- Current blocking chains on SQL MI
SELECT
    blocked.session_id AS blocked_session_id,
    blocked.blocking_session_id,
    blocked.wait_type,
    blocked.wait_time / 1000 AS wait_time_sec,
    DB_NAME(blocked.database_id) AS database_name,
    SUBSTRING(blocked_text.text,
        (blocked.statement_start_offset / 2) + 1,
        ((CASE blocked.statement_end_offset
            WHEN -1 THEN DATALENGTH(blocked_text.text)
            ELSE blocked.statement_end_offset
          END - blocked.statement_start_offset) / 2) + 1
    ) AS blocked_statement,
    SUBSTRING(blocker_text.text,
        (blocker.statement_start_offset / 2) + 1,
        ((CASE blocker.statement_end_offset
            WHEN -1 THEN DATALENGTH(blocker_text.text)
            ELSE blocker.statement_end_offset
          END - blocker.statement_start_offset) / 2) + 1
    ) AS blocker_statement
FROM sys.dm_exec_requests AS blocked
INNER JOIN sys.dm_exec_requests AS blocker
    ON blocked.blocking_session_id = blocker.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) AS blocked_text
CROSS APPLY sys.dm_exec_sql_text(blocker.sql_handle) AS blocker_text
WHERE blocked.blocking_session_id <> 0;
```

### Query 4 — Detect deadlocks via Extended Events or system health (SQL MI)

To review recent deadlocks on SQL MI, query the `system_health` Extended Events session which captures deadlock graphs automatically:

```sql
-- Recent deadlocks from system_health XE session
SELECT
    xdr.value('@timestamp', 'datetime2') AS deadlock_time,
    xdr.query('.') AS deadlock_graph
FROM (
    SELECT CAST(target_data AS XML) AS target_data
    FROM sys.dm_xe_session_targets AS st
    INNER JOIN sys.dm_xe_sessions AS s
        ON s.address = st.event_session_address
    WHERE s.name = 'system_health'
      AND st.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS xevt(xdr)
ORDER BY deadlock_time DESC;
```

> **Tip:** For production workloads, consider creating a dedicated Extended Events session to capture blocking and deadlock events with richer detail than the `system_health` session provides.

### Query 5 — Query Store wait stats trend

This query trends waits by category so you can distinguish CPU, IO, lock, memory, and log pressure over time.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == "QueryStoreWaitStatistics"
| extend database_name = coalesce(DatabaseName_s, Resource)
| extend wait_category = coalesce(wait_category_s, wait_category_desc_s, "unknown")
| extend total_wait_ms = todouble(total_query_wait_time_ms_d)
| summarize total_wait_ms = sum(total_wait_ms) by database_name, wait_category, bin(TimeGenerated, 15m)
| order by TimeGenerated asc
| render timechart
```

![KQL wait stats trend chart](../../Images/c4-step4-SQLMI-WaitStats-Chart.png)

## Step 6 — Use Query Store for regression analysis
Query Store is supported on Azure SQL Managed Instance and is the best built-in feature for query regression analysis because it persists query text, runtime statistics, waits, and plans over time.

Query Store is **enabled by default** on Azure SQL MI for newly created and migrated databases. Verify and adjust the configuration for the lab:

```sql
-- Clear all existing Query Store data
ALTER DATABASE AdventureWorks2019 SET QUERY_STORE CLEAR ALL;
GO

-- Configure Query Store to capture ALL queries immediately
ALTER DATABASE AdventureWorks2019
SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,              -- Capture everything
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 1,           -- Short intervals for quick results
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200,
    DATA_FLUSH_INTERVAL_SECONDS = 60
);
GO
```

Now we are going to generate load to see a query with different executions plans:

```sql
-- Clear all existing Query Store data
ALTER DATABASE AdventureWorks2019 SET QUERY_STORE CLEAR ALL;
GO

-- Configure Query Store to capture ALL queries immediately
ALTER DATABASE AdventureWorks2019
SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,              -- Capture everything
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 1,           -- Short intervals for quick results
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200,
    DATA_FLUSH_INTERVAL_SECONDS = 60
);
GO
```


Now we create a stored procedure to run a specifc query, first with the needed indexing for performance and then, dropping this index to verify the performance degradation:

```sql
DROP PROCEDURE IF EXISTS dbo.usp_GetSalesOrdersByCustomer;
GO

CREATE PROCEDURE dbo.usp_GetSalesOrdersByCustomer
    @CustomerID INT = 29825  -- Default customer with many orders
AS
BEGIN
    SET NOCOUNT ON;
    
    -- This query will perform DRAMATICALLY differently with/without index
    -- With index: Index Seek (milliseconds)
    -- Without index: Table Scan of 31K+ rows (much slower)
    
    SELECT 
        soh.SalesOrderID,
        soh.OrderDate,
        soh.DueDate,
        soh.ShipDate,
        soh.Status,
        soh.SubTotal,
        soh.TaxAmt,
        soh.Freight,
        soh.TotalDue,
        c.AccountNumber,
        p.FirstName + ' ' + p.LastName AS CustomerName,
        st.Name AS TerritoryName,
        COUNT(sod.SalesOrderDetailID) AS LineItemCount,
        SUM(sod.LineTotal) AS OrderLineTotal
    FROM Sales.SalesOrderHeader soh
    INNER JOIN Sales.Customer c ON soh.CustomerID = c.CustomerID
    INNER JOIN Person.Person p ON c.PersonID = p.BusinessEntityID
    LEFT JOIN Sales.SalesTerritory st ON soh.TerritoryID = st.TerritoryID
    INNER JOIN Sales.SalesOrderDetail sod ON soh.SalesOrderID = sod.SalesOrderID
    WHERE soh.CustomerID = @CustomerID
    GROUP BY 
        soh.SalesOrderID,
        soh.OrderDate,
        soh.DueDate,
        soh.ShipDate,
        soh.Status,
        soh.SubTotal,
        soh.TaxAmt,
        soh.Freight,
        soh.TotalDue,
        c.AccountNumber,
        p.FirstName,
        p.LastName,
        st.Name
    ORDER BY soh.OrderDate DESC;
END;
GO

-- Check if the critical index exists
IF NOT EXISTS (
    SELECT 1 
    FROM sys.indexes 
    WHERE name = 'IX_SalesOrderHeader_CustomerID' 
    AND object_id = OBJECT_ID('Sales.SalesOrderHeader')
)
BEGIN
    PRINT 'Index does not exist - creating it...';
    CREATE NONCLUSTERED INDEX IX_SalesOrderHeader_CustomerID 
    ON Sales.SalesOrderHeader (CustomerID)
    INCLUDE (OrderDate, TotalDue, Status, SubTotal, TaxAmt, Freight, DueDate, ShipDate, TerritoryID, SalesOrderID);
    PRINT 'Index created successfully.';
END
ELSE
BEGIN
    PRINT 'Index already exists - ready for baseline testing.';
END
```

Now we will execute the procedure 40 times, to get result for the optimized query:

```sql
-- Clear execution plan cache to ensure fresh execution
DBCC FREEPROCCACHE;
GO

-- Execute multiple times to establish a solid baseline
EXEC dbo.usp_GetSalesOrdersByCustomer @CustomerID = 29825;
GO 30  -- Run 30 times
```

Now we check the baseline performance:

```sql
SELECT 
    'BASELINE (with index)' AS Phase,
    COUNT(rs.plan_id) AS Executions,
    AVG(rs.avg_duration) / 1000.0 AS AvgDurationMs,
    AVG(rs.avg_cpu_time) / 1000.0 AS AvgCpuMs,
    AVG(rs.avg_logical_io_reads) AS AvgLogicalReads
FROM sys.query_store_query q
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE q.object_id = OBJECT_ID('dbo.usp_GetSalesOrdersByCustomer');
```

Now, we drop the index and execute the Stored Procedure 30 times :

```sql
DROP INDEX IX_SalesOrderHeader_CustomerID ON Sales.SalesOrderHeader;
GO


-- Clear plan cache to force recompile with new (worse) plan
DBCC FREEPROCCACHE;
GO


EXEC dbo.usp_GetSalesOrdersByCustomer @CustomerID = 29825;
GO 30  -- Run 30 times with poor performance
```

Now we can see the times it took to execute the query depending on the plan:

```sql
SELECT TOP 5
    q.query_id,
    OBJECT_NAME(q.object_id) AS StoredProcedure,
    p.plan_id,
    rs.runtime_stats_interval_id,
    rsi.start_time AS IntervalStart,
    rs.count_executions AS Executions,
    rs.avg_duration / 1000.0 AS AvgDurationMs,
    rs.avg_cpu_time / 1000.0 AS AvgCpuMs,
    rs.avg_logical_io_reads AS AvgLogicalReads,
    rs.avg_physical_io_reads AS AvgPhysicalReads,
    TRY_CAST(p.query_plan AS XML) AS QueryPlan
FROM sys.query_store_query q
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE q.object_id = OBJECT_ID('dbo.usp_GetSalesOrdersByCustomer')
ORDER BY rsi.start_time, p.plan_id;
```

The previous query returns both queries and the execution plans associated, as well as the times it the query took

![SSMS Query Store highest consumption](../../Images/c4-step-13-query-store-queries-highest-consumption.png)


In the following figure we can see how the current query (in our case, query 3) presents the two execution plans. Plan 4 presents worse times, as it is the one without the index. From this screen, navigate to the plans ans explore the differences:

![SSMS Query Store highest consumption 2](../../Images/c4-step-14-query-store-queries-highest-consumption2.png)

Compare the previous plan and current plan. If a known good plan is available, force it from the SSMS report or use T-SQL.

![SSMS Query Store highest consumption 2](../../Images/c4-step-15-query-store-force-plan-execution.png)

## Step 7 — Configure Automatic Tuning + alerts

Automatic tuning can help stabilize workloads by automatically correcting plan regressions. On Azure SQL Managed Instance, the only supported automatic tuning option is **`FORCE_LAST_GOOD_PLAN`** (automatic plan correction). 

Enable automatic plan correction using T-SQL:

```sql
ALTER DATABASE AdventureWorks2019 SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
GO

SELECT name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;
```

The T-SQL query above (`sys.database_automatic_tuning_options`) is the way to confirm the setting on Managed Instance.

Next, create an Azure Monitor alert. Open **Monitoring** → **Alerts** → **Create** → **Alert rule**. Use scope `sqlmi-microhack-2026`, signal **Average CPU percentage**, threshold **Greater than 80**, aggregation **Average**, evaluation frequency **1 minute**, and lookback/window **5 minutes**.

![Create alert rule condition](../../Images/c4-step7-SQLMI-Alert-Rule.png)

Create or select an action group named `ag-microhack-sql-ops`. Add an email receiver for the lab operator. 

REMOVE!!!!!For Teams notifications, use a **Workflows connector** (Power Automate) instead of the deprecated Office 365 Incoming Webhooks — create a workflow in Teams that posts to a channel when triggered by an HTTP request, then add that workflow URL as a webhook receiver in the action group. Name the alert `sqlmi-high-cpu-80pct-10m` and set severity to 2.

![Alert action group email teams](../../Images/c4-step7-SQLMI-Alert-Action-Group.png)

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

---

## Bonus Step 9 — Explore Database Watcher (preview, optional)

> **Prerequisites:** This step is optional and intended for teams that finish Steps 1–8 early. Database Watcher is currently in **preview** and is only available in a subset of Azure regions (Americas: Canada Central, Canada East, Central US, East US, East US 2, North Central US, West US; plus select EMEA and APAC regions). If your SQL MI is deployed in an unsupported region, you can still create a watcher in a nearby supported region — it can monitor targets cross-region. This step also requires an Azure Data Explorer cluster (a free cluster works for the lab) or Real-Time Analytics in Microsoft Fabric.

Database Watcher is Microsoft's purpose-built monitoring solution for Azure SQL workloads. Unlike diagnostic settings that stream logs to Log Analytics, Database Watcher collects data from **70+ DMVs and catalog views** directly into an Azure Data Explorer database, providing richer datasets (Active Sessions, Top Queries, Wait Stats, Index Metadata, Backup History, and more) with built-in dashboards in the Azure portal.

### 9a — Create a free Azure Data Explorer cluster

If your lab subscription does not already have an Azure Data Explorer cluster, create a **free cluster** for this step (no SLA, but sufficient for the lab):

1. Navigate to [https://aka.ms/kustofree](https://aka.ms/kustofree) and sign in.
2. Create a free cluster. Note the cluster URI and the default database name.

> **Note:** Creating the free cluster from the link above avoids a known portal issue where the cluster shows a 403-Forbidden error in the ADX web UI.

If you prefer a provisioned cluster, create a Dev/test SKU Azure Data Explorer cluster in the same region as your SQL MI to minimize network costs.

### 9b — Create a Database Watcher

1. In the Azure portal, search for **Database Watchers** and select **Create**.
2. Choose the subscription and resource group `rg-microhack-sql-2026`.
3. Name the watcher `dbw-microhack-sql`.
4. Select a supported region (same as your SQL MI if possible).
5. Under **Data store**, select your Azure Data Explorer cluster and database.
6. Select **Review + create** → **Create**.

### 9c — Add SQL MI as a target

1. Open the watcher `dbw-microhack-sql` → **SQL targets** → **Add**.
2. Select **SQL managed instance** → `sqlmi-microhack-2026`.
3. Choose **Microsoft Entra authentication** (recommended) or SQL authentication.
4. If using public connectivity, ensure the SQL MI public endpoint is enabled and the NSG allows inbound traffic on TCP port 3342 from `AzureCloud`.
5. Save the target.

### 9d — Grant watcher access to SQL MI

The watcher needs a dedicated login with specific, limited permissions. Connect to the SQL MI `master` database and run the following T-SQL (replace the watcher identity with the managed identity name shown on the watcher's **Identity** page):

```sql
-- Replace 'dbw-microhack-sql' with your watcher's managed identity name.
CREATE LOGIN [dbw-microhack-sql] FROM EXTERNAL PROVIDER;

-- Grant required server roles
ALTER SERVER ROLE ##MS_ServerPerformanceStateReader## ADD MEMBER [dbw-microhack-sql];
ALTER SERVER ROLE ##MS_DefinitionReader## ADD MEMBER [dbw-microhack-sql];
ALTER SERVER ROLE ##MS_DatabaseConnector## ADD MEMBER [dbw-microhack-sql];
GO
```

Grant access to `msdb` tables for backup and SQL Agent history:

```sql
USE msdb;
GO
CREATE USER [dbw-microhack-sql] FOR LOGIN [dbw-microhack-sql];
GO
GRANT SELECT ON dbo.backupmediafamily TO [dbw-microhack-sql];
GRANT SELECT ON dbo.backupmediaset TO [dbw-microhack-sql];
GRANT SELECT ON dbo.backupset TO [dbw-microhack-sql];
GRANT SELECT ON dbo.suspect_pages TO [dbw-microhack-sql];
GRANT SELECT ON dbo.syscategories TO [dbw-microhack-sql];
GRANT SELECT ON dbo.sysjobactivity TO [dbw-microhack-sql];
GRANT SELECT ON dbo.sysjobhistory TO [dbw-microhack-sql];
GRANT SELECT ON dbo.sysjobs TO [dbw-microhack-sql];
GRANT SELECT ON dbo.sysjobsteps TO [dbw-microhack-sql];
GRANT SELECT ON dbo.sysoperators TO [dbw-microhack-sql];
GRANT SELECT ON dbo.syssessions TO [dbw-microhack-sql];
GO
```

> **Important:** Do not add the watcher login to any other roles or grant additional permissions beyond those listed above. The watcher validates its exact permission set on connection and will **disconnect** if it detects unexpected permissions.

### 9e — Start the watcher and explore dashboards

1. Return to the watcher **Overview** page and select **Start**.
2. Wait 5–10 minutes for the first data collection cycle to complete.
3. Open the **Dashboards** page. You should see:
   - **Estate dashboard** — a heatmap of CPU utilization across all monitored targets.
   - **Resource dashboard** — click into `sqlmi-microhack-2026` for detailed tabs: Performance, Active Sessions, Top Queries, Wait Statistics, Backup History, and more.

4. Navigate to the **Top Queries** tab. Compare the top CPU consumers shown here with the DMV results from Step 3 and the Query Store data from Step 6. You should see the same synthetic procedures (`usp_MicroHackCpuPressure`, `usp_MicroHackCursorPressure`) appearing in the Database Watcher view.

### 9f — Run a KQL query on the watcher data store

From the watcher **Dashboards** page, expand the **Data store** section and copy the **Kusto query URI**. Open the [Azure Data Explorer web UI](https://dataexplorer.azure.com/) and connect to that URI.

Run a query to compare the Top Queries dataset with your Log Analytics results from Step 5:

```kusto
// Top CPU-consuming queries from the Database Watcher Top queries dataset.
sqlmi_query_runtime_stats
| where sample_time_utc > ago(2h)
| summarize
    total_cpu_ms = sum(total_cpu_time_ms),
    total_executions = sum(count_executions),
    avg_duration_ms = avg(avg_duration_ms)
    by query_hash, query_sql_text = tostring(query_sql_text)
| top 10 by total_cpu_ms desc
```

> **Note:** Database Watcher dataset table names (e.g., `sqlmi_query_runtime_stats`, `sqlmi_active_sessions`, `sqlmi_wait_stats`) differ from the `AzureDiagnostics` category names used in Log Analytics. See [Database watcher data collection and datasets](https://learn.microsoft.com/en-us/azure/azure-sql/database-watcher-data?view=azuresql) for the full schema reference.

### What to compare

| Aspect | Diagnostic Settings + Log Analytics (Steps 1–5) | Database Watcher (Step 9) |
|--------|--------------------------------------------------|---------------------------|
| **Data source** | Diagnostic log categories streamed to `AzureDiagnostics` table | 70+ DMV/catalog view datasets collected into ADX tables |
| **Query engine** | Log Analytics (KQL on Azure Monitor Logs) | Azure Data Explorer (native KQL) |
| **Dashboards** | Custom workbooks or manual KQL | Built-in portal dashboards with heatmaps, Top Queries, drill-through |
| **Setup effort** | Diagnostic setting + Log Analytics workspace | Watcher + ADX cluster + SQL target + RBAC grants |
| **Cost model** | Log Analytics ingestion per GB | ADX cluster SKU (or free cluster) |
| **Status** | GA | Preview |
| **Best for** | Centralized log correlation, alerting, long-term retention | Deep SQL-specific monitoring, fleet views, rich query analytics |

In production, these approaches are **complementary**: diagnostic settings provide integration with Azure Monitor alerts and cross-service log correlation, while Database Watcher delivers deeper SQL-specific observability. For this lab, Steps 1–8 cover the production-ready path; Database Watcher adds a forward-looking preview of what fleet monitoring looks like.

---

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
- [Quickstart: Create a watcher to monitor Azure SQL (preview)](https://learn.microsoft.com/en-us/azure/azure-sql/database-watcher-quickstart?view=azuresql)
- [Create and configure a database watcher (preview)](https://learn.microsoft.com/en-us/azure/azure-sql/database-watcher-manage?view=azuresql)
- [Database watcher data collection and datasets (preview)](https://learn.microsoft.com/en-us/azure/azure-sql/database-watcher-data?view=azuresql)

---

[Previous Solution](../challenge-03/solution-03.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-05/solution-05.md)
