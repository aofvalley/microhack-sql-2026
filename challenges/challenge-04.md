# Challenge 4 — Monitoring and Performance on Azure SQL Managed Instance

[Previous](challenge-03.md) - **[Home](../Readme.md)** - [Next Challenge](challenge-05.md)

## Goal

The goal of this exercise is to understand monitoring and performance optimization on Azure SQL Managed Instance using Azure Monitor for SQL, Database Watcher preview, and KQL.

## Actions

* Identify performance issues, their root causes, and possible fixes
* Use Azure Portal, Azure Monitor metrics, and Query Store to identify performance bottlenecks
* Use Log Analytics or Database Watcher data with KQL to visualize Azure SQL MI and database statistics

## Success criteria

* You identified the most expensive stored procedure based on total CPU usage (`total_worker_time`)
* You reviewed CPU utilization and related metrics in Azure Monitor
* You queried SQL monitoring data with KQL and produced at least one useful table or chart

## Learning resources

* [Monitor Azure SQL Managed Instance with Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/monitoring-sql-managed-instance-azure-monitor?view=azuresql)
* [Monitor Azure SQL workloads with Database Watcher](https://learn.microsoft.com/en-us/azure/azure-sql/database-watcher-overview?view=azuresql)
* [Analyze monitoring data with KQL](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
* [Query Store best practices](https://learn.microsoft.com/en-us/sql/relational-databases/performance/best-practice-with-the-query-store?view=sql-server-ver17)
