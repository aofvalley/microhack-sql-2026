/*
    MicroHack SQL Modernization 2026 — Dirty workload script (per-team parametrized)
    Purpose: introduce realistic assessment findings in the sample databases.

    Usage (deploy.ps1 invokes via RunCommand):
        sqlcmd -S localhost -E -v TeamPrefix=TEAM01 -i dirty-workload.sql

    Standalone per-team run:
        sqlcmd -S 10.0.2.4 -U team01 -P <pass> -v TeamPrefix=TEAM01 -i dirty-workload.sql

    Adapted from Solution 1 Annex A.
*/

:setvar TeamPrefix "TEAM01"

USE master;
GO

PRINT 'Enable advanced options and CLR for lab assessment findings';
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

PRINT 'Enable lab trace flags for assessment discussion';
DBCC TRACEON(1117, -1);
DBCC TRACEON(1118, -1);
DBCC TRACEON(4199, -1);
GO

PRINT 'Verify team databases exist before proceeding';
IF DB_ID(N'$(TeamPrefix)_AdventureWorks2019') IS NULL
   OR DB_ID(N'$(TeamPrefix)_WideWorldImporters') IS NULL
BEGIN
    THROW 51000, 'Team databases not found. Run setup-team-dbs.ps1 first.', 1;
END;
GO

-- Cross-database view and procedure: AdventureWorks -> WideWorldImporters
USE [$(TeamPrefix)_AdventureWorks2019];
GO

CREATE OR ALTER VIEW Sales.vCustomerFromWWI
AS
SELECT TOP (100)
       p.BusinessEntityID,
       p.FirstName,
       p.LastName,
       c.CustomerID   AS WWI_CustomerID,
       c.CustomerName AS WWI_CustomerName
FROM   Person.Person AS p
CROSS JOIN [$(TeamPrefix)_WideWorldImporters].Sales.Customers AS c;
GO

CREATE OR ALTER PROCEDURE Sales.usp_CrossDatabaseCustomerSample
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (25)
           BusinessEntityID,
           FirstName,
           LastName,
           WWI_CustomerName
    FROM   Sales.vCustomerFromWWI
    ORDER BY BusinessEntityID;
END;
GO

-- CLR placeholder in team admin database
USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$(TeamPrefix)_MicroHackAdmin')
    CREATE DATABASE [$(TeamPrefix)_MicroHackAdmin];
GO

USE [$(TeamPrefix)_MicroHackAdmin];
GO

CREATE OR ALTER PROCEDURE dbo.usp_ClrFindingPlaceholder
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 'CLR enabled; documents where a real CLR assembly would be assessed.' AS Finding;
END;
GO

-- Deprecated crypto / TDE objects for remediation discussion
USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ReplaceThis-LabOnly-Password-2026!';
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'MicroHackLegacyTDECert')
    CREATE CERTIFICATE MicroHackLegacyTDECert
        WITH SUBJECT = 'MicroHack legacy TDE cert for migration assessment discussion';
GO

-- SQL Agent workload job
USE msdb;
GO

DECLARE @jobName nvarchar(128) = N'MicroHack - $(TeamPrefix) read workload';
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @jobName)
    EXEC dbo.sp_delete_job @job_name = @jobName;
GO

DECLARE @jobId   uniqueidentifier;
DECLARE @jobName nvarchar(128) = N'MicroHack - $(TeamPrefix) read workload';

EXEC dbo.sp_add_job
    @job_name    = @jobName,
    @enabled     = 1,
    @description = N'Light read workload for assessment and migration validation.',
    @job_id      = @jobId OUTPUT;

EXEC dbo.sp_add_jobstep
    @job_id        = @jobId,
    @step_name     = N'Revenue query',
    @subsystem     = N'TSQL',
    @database_name = N'$(TeamPrefix)_AdventureWorks2019',
    @command       = N'
SELECT TOP (20) CustomerID, SUM(TotalDue) AS Revenue
FROM   Sales.SalesOrderHeader
GROUP  BY CustomerID
ORDER  BY Revenue DESC;',
    @retry_attempts = 0,
    @retry_interval = 0;

EXEC dbo.sp_add_schedule
    @schedule_name       = N'MicroHack $(TeamPrefix) every 5min',
    @enabled             = 1,
    @freq_type           = 4,
    @freq_interval       = 1,
    @freq_subday_type    = 4,
    @freq_subday_interval = 5;

EXEC dbo.sp_attach_schedule
    @job_id        = @jobId,
    @schedule_name = N'MicroHack $(TeamPrefix) every 5min';

EXEC dbo.sp_add_jobserver
    @job_id      = @jobId,
    @server_name = N'(LOCAL)';
GO

PRINT 'Dirty workload injection complete for $(TeamPrefix)';
GO
