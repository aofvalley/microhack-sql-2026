/*
    Creates a SQL login for one team and grants db_owner on all team databases.

    Usage (deploy.ps1 invokes per team):
        sqlcmd -S localhost -E -v TeamPrefix=TEAM01 -v TeamLogin=team01 -v TeamPassword=<pass> -i grant-team-permissions.sql

    Idempotent: safely re-runs if login or user already exists.
*/

:setvar TeamPrefix   "TEAM01"
:setvar TeamLogin    "team01"
:setvar TeamPassword "TeamPass01!"

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$(TeamLogin)')
BEGIN
    CREATE LOGIN [$(TeamLogin)]
        WITH PASSWORD     = N'$(TeamPassword)',
             CHECK_POLICY  = OFF,
             DEFAULT_DATABASE = master;
    PRINT 'Login created: $(TeamLogin)';
END
ELSE
    PRINT 'Login already exists: $(TeamLogin)';
GO

-- Grant db_owner on each team database that exists on this instance
DECLARE @dbs TABLE (dbname nvarchar(128));
INSERT @dbs VALUES
    (N'$(TeamPrefix)_AdventureWorks2019'),
    (N'$(TeamPrefix)_WideWorldImporters'),
    (N'$(TeamPrefix)_MicroHackAdmin');

DECLARE @db  nvarchar(128);
DECLARE @sql nvarchar(max);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT dbname FROM @dbs;
OPEN cur;
FETCH NEXT FROM cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF DB_ID(@db) IS NOT NULL
    BEGIN
        SET @sql = N'
USE [' + @db + N'];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''$(TeamLogin)'')
    CREATE USER [$(TeamLogin)] FOR LOGIN [$(TeamLogin)];
EXEC sp_addrolemember ''db_owner'', ''$(TeamLogin)'';
';
        EXEC sp_executesql @sql;
        PRINT 'db_owner on: ' + @db;
    END
    FETCH NEXT FROM cur INTO @db;
END

CLOSE cur;
DEALLOCATE cur;
GO

PRINT 'grant-team-permissions complete for $(TeamLogin)';
GO
