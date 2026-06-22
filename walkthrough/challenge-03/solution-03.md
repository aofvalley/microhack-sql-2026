# Solution 3 — Managed Instance Link migration (SQL Server 2025 → Azure SQL Managed Instance)

[Previous Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-04/solution-04.md)

> Outline
>
> 1. Confirm prerequisites on the source SQL Server 2025 (version, trace flags, AG feature).
> 2. Generate or reuse a Database Master Key and TDE certificate on the source.
> 3. Create the database mirroring endpoint on the source.
> 4. Provision (or reuse) the target Azure SQL Managed Instance.
> 5. Create the MI link from SQL Server Management Studio.
> 6. Monitor link health and replication lag.
> 7. Perform a planned failover and validate the database is writable on MI.
> 8. Drop the link to make the cutover permanent.

## Overview

Use the link feature to replicate databases from your initial primary to your secondary replica. For SQL Server 2022, the initial primary can be either SQL Server or Azure SQL Managed Instance. For SQL Server 2019 and earlier versions, the initial primary must be SQL Server. After you configure the link, the database from the initial primary replicates to the secondary replica.

You can choose to leave the link in place for continuous data replication in a hybrid environment between the primary and secondary replica, or you can fail over the database to the secondary replica, to migrate to Azure or for disaster recovery. For SQL Server 2019 and earlier versions, failing over to Azure SQL Managed Instance breaks the link and fail back isn't supported. With SQL Server 2022 and SQL Server 2025, you have the option to maintain the link and fail back and forth between the two replicas.

If you plan to use your secondary managed instance for only disaster recovery, you can save on licensing costs by activating the hybrid failover benefit.

After you create the link, your source database gets a read-only copy on your target secondary replica.

Some things to consider:

- The link feature supports one database per link. To replicate multiple databases from an instance, create a link for each individual database. For example, to replicate 10 databases to SQL Managed Instance, create 10 individual links.
- Collation between SQL Server and SQL Managed Instance should be the same. A mismatch in collation can cause a mismatch in server name casing and prevent a successful connection from SQL Server to SQL Managed Instance.
- Error 1475 on your initial SQL Server primary indicates that you need to start a new backup chain by creating a full backup without the COPY ONLY option.
- To establish a link, or fail over, from SQL Managed Instance to SQL Server 2025, you must configure your SQL managed instance with the SQL Server 2025 update policy. Data replication and failover from SQL Managed Instance to SQL Server 2025 isn't supported by instances configured with a mismatched update policy.
- To establish a link, or fail over, from SQL Managed Instance to SQL Server 2022, you must configure your SQL managed instance with the SQL Server 2022 update policy. Data replication and failover from SQL Managed Instance to SQL Server 2022 isn't supported by instances configured with a mismatched update policy.
- While you can establish a link from a supported version of SQL Server to a SQL managed instance configured with the Always-up-to-date update policy, after failover to SQL Managed Instance, you can't replicate data or fail back to your SQL Server instance.

## Architecture

![managed instance link architecture](../../Images/c3-architecture.png)

## Prerequisites

To replicate your databases to your secondary replica through the link, you need the following prerequisites:

- An active Azure subscription
- A [supported version of SQL Server](#supported-versions-of-sql-server) with required service update installed
- An Azure SQL Managed Instance
- [SQL Server Management Studio](https://learn.microsoft.com/en-us/ssms/sql-server-management-studio-ssms) v19.2 or later

### Supported versions of SQL Server

| Initial primary version | Operating system (OS) | Disaster recovery options | Minimum required servicing update |
| - | - | - | - |
| Azure SQL Managed Instance | Windows Server and Linux for the secondary SQL Server instance replica | Bi-directional | Configuring a link from Azure SQL Managed Instance to, and bidirectional failover with, is supported by:  <br>- SQL Server 2025 and SQL MI with the SQL Server 2025 update policy<br>- SQL Server 2022 and SQL MI with the SQL Server 2022 update policy |
| SQL Server 2025 (17.x) | Windows Server and Linux | Bi-directional | [SQL Server 2025 RTM (17.0.1000.7)](https://learn.microsoft.com/en-us/sql/sql-server/sql-server-2025-release-notes) |
| SQL Server 2022 (16.x) | Windows Server and Linux | Bi-directional | - [SQL Server 2022 RTM (16.0.1000.6)](https://learn.microsoft.com/en-us/sql/sql-server/sql-server-2022-release-notes): Creating a link from SQL Server 2022 to SQL MI  <br>- [SQL Server 2022 CU10 (16.0.4095.4)](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2022/cumulativeupdate10): Creating a link from SQL MI to SQL Server 2022 [^1]<br>- [SQL Server 2022 CU13 (16.0.4125.3)](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2022/cumulativeupdate13): Failing over the link using [Transact-SQL](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-failover-how-to?view=azuresql&tabs=tsql#fail-over-a-database) |
| SQL Server 2019 (15.x) | Windows Server and Linux | From SQL Server to SQL MI only | [SQL Server 2019 CU20 (15.0.4312.2)](https://support.microsoft.com/topic/kb5024276-cumulative-update-20-for-sql-server-2019-4b282be9-b559-46ac-9b6a-badbd44785d2) |
| SQL Server 2017 (14.x) | Windows Server and Linux | From SQL Server to SQL MI only | [SQL Server 2017 CU31 (14.0.3456.2)](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2017/cumulativeupdate31) and the matching [SQL Server 2017 Azure Connect pack (14.0.3490.10)](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2017/azureconnect) |
| SQL Server 2016 (13.x) | Windows Server and Linux | From SQL Server to SQL MI only | [SQL Server 2016 SP3 (13.0.6300.2)](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2016/build-versions#sql-server-2016-service-pack-3-sp3-cumulative-update-cu-builds) and the matching [SQL Server 2016 Azure Connect pack (13.0.7000.253)](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2016/build-versions#sql-server-2016-service-pack-3-sp3-azure-connect-pack-builds) |
| SQL Server 2014 (12.x) and earlier | N/A | N/A | Versions before SQL Server 2016 aren't supported. |

[^1]: While creating a link with SQL Server 2022 as the initial primary is supported starting with the RTM version of SQL Server 2022, creating a link with Azure SQL Managed Instance as the initial primary is supported only starting with SQL Server 2022 CU10. If you create the link from a SQL Managed Instance initial primary, downgrading SQL Server below CU10 isn't supported while the link is active as it can cause issues after failing over in either direction.

### Permissions

For SQL Server, you need sysadmin permissions. The provided admin user has this permission.

For Azure SQL Managed Instance, you need to be a member of the SQL Managed Instance Contributor role (the provided admin user has this role), or have the following custom role permissions:

|Microsoft.Sql/ resource|Necessary permissions|
|-|-|
|Microsoft.Sql/managedInstances|/read, /write|
|Microsoft.Sql/managedInstances/hybridCertificate|/action|
|Microsoft.Sql/managedInstances/databases|/read, /delete, /write, /completeRestore/action, /readBackups/action, /restoreDetails/read|
|Microsoft.Sql/managedInstances/distributedAvailabilityGroups|/read, /write, /delete, /setRole/action|
|Microsoft.Sql/managedInstances/endpointCertificates|/read|
|Microsoft.Sql/managedInstances/hybridLink|/read, /write, /delete|
|Microsoft.Sql/managedInstances/serverTrustCertificates|/write, /delete, /read|

## Task: Enable local firewall inbound rule for port 5022

Create an inbound Windows Firewall rule on the source SQL Server 2025 VM to allow TCP 5022. This port is required by the database mirroring endpoint used by SQL Managed Instance link, so opening it ensures replication traffic can reach the source instance during link creation and synchronization.

![New rule wizard](../../Images/c3-step1.0-windows-firewall.png)
![New rule wizard](../../Images/c3-step1.0-rule-wizard-1.png)
![New rule wizard](../../Images/c3-step1.0-rule-wizard-2.png)
![New rule wizard](../../Images/c3-step1.0-rule-wizard-3.png)
![New rule wizard](../../Images/c3-step1.0-rule-wizard-4.png)
![New rule wizard](../../Images/c3-step1.0-rule-wizard-5.png)

## Task: Ensure Agent Service is running

Start and verify SQL Server Agent on the source VM. Managed Instance link uses SQL Agent jobs for parts of the setup and ongoing operations, so this service must be running to create the link successfully and keep replication tasks healthy.

![Enable Agent service](../../Images/c3-step2.0-agent-service-1.png)
![Enable Agent service](../../Images/c3-step2.0-agent-service-2.png)

## Task: Create database master key

Create a Database Master Key in the master database to protect cryptographic objects used by the link setup. This is a prerequisite for securely creating and storing endpoint certificates that enable encrypted communication between SQL Server 2025 and Azure SQL Managed Instance.

``` sql
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong_password>';
```

![Create database master key](../../Images/c3-step3.0-database-master-key-1.png)

``` sql
USE master;
GO
SELECT * FROM sys.symmetric_keys WHERE name LIKE '%DatabaseMasterKey%';
```

![Create database master key](../../Images/c3-step3.0-database-master-key-2.png)

## Task: Enable Accelerated Database Recovery

Enable Accelerated Database Recovery (ADR) on the source database. ADR improves transaction recovery behavior and is required for this migration pattern, helping the source database meet SQL Managed Instance link prerequisites before seeding and replication begin.

![Enable Accelerated Database Recovery](../../Images/c3-step4.0-accelerated-database-recovery-1.png)

## Task: Create Database Mirroring endpoint

Create a certificate-based database mirroring endpoint on the source SQL Server instance. This endpoint listens on port 5022 and establishes the secure transport channel required by SQL Managed Instance link to send transaction log changes from the source VM to the target managed instance.

``` sql
USE master
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'MILinkCert')
BEGIN
    CREATE CERTIFICATE MILinkCert
    WITH SUBJECT = 'MI Link mirroring endpoint cert',
    EXPIRY_DATE = '2099-12-31';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_mirroring_endpoints WHERE name = 'dbmirroring_endpoint')
BEGIN
    CREATE ENDPOINT [dbmirroring_endpoint]
    STATE = STARTED
    AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL)
    FOR DATABASE_MIRRORING (
        AUTHENTICATION = CERTIFICATE MILinkCert,
        ENCRYPTION = REQUIRED ALGORITHM AES,
        ROLE = ALL
    );
END
GO
```

![Create Database Mirroring endpoint](../../Images/c3-step5.0-database-mirroring-endpoint-1.png)

## Task: Enable Always-on Availability Groups

Enable the Always On Availability Groups feature on the source SQL Server 2025 instance and restart services if needed. SQL Managed Instance link depends on AG technologies under the hood, so this step activates the high-availability components required to initialize and maintain the link.

![Enable Always-on Availability Groups](../../Images/c3-step6.0-alwayson-ag-1.png)

![Enable Always-on Availability Groups](../../Images/c3-step6.0-alwayson-ag-2.png)

![Enable Always-on Availability Groups](../../Images/c3-step6.0-alwayson-ag-3.png)

![Enable Always-on Availability Groups](../../Images/c3-step6.0-alwayson-ag-4.png)

## Task: Enable startup trace flags

Configure the required startup trace flags in SQL Server Configuration Manager for the source instance. These flags enable behavior needed by SQL Managed Instance link scenarios, ensuring the source engine starts with the correct settings before link creation and failover operations.

![Enable startup trace flags](../../Images/c3-step7.0-trace-flags-1.png)

![Enable startup trace flags](../../Images/c3-step7.0-trace-flags-2.png)

![Enable startup trace flags](../../Images/c3-step7.0-trace-flags-3.png)

![Enable startup trace flags](../../Images/c3-step7.0-trace-flags-4.png)

![Enable startup trace flags](../../Images/c3-step7.0-trace-flags-5.png)

## Task: Perform a full database backup

Take a full backup of the source database to start a valid backup chain. SQL Managed Instance link setup relies on this chain for initial seeding and synchronization, so this backup ensures the target can initialize correctly and avoid backup-chain related errors during migration.

![Full database backup](../../Images/c3-step8.0-db-backup-1.png)

![Full database backup](../../Images/c3-step8.0-db-backup-2.png)

![Full database backup](../../Images/c3-step8.0-db-backup-3.png)

![Full database backup](../../Images/c3-step8.0-db-backup-4.png)

## Task: Test network connection

Validate end-to-end network connectivity between the source SQL Server VM and Azure SQL Managed Instance, including DNS resolution and TCP reachability on required ports. This confirms that endpoint traffic can flow and helps detect NSG, routing, or firewall issues before creating the link.

![Test network connection](../../Images/c3-step9.0-test-nw-connection-1.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-2.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-3.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-4.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-5.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-6.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-7.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-8.png)

![Test network connection](../../Images/c3-step9.0-test-nw-connection-9.png)

## Task: Create Azure SQL Managed Instance link

Use SQL Server Management Studio to create the SQL Managed Instance link from the source SQL Server 2025 database to the target managed instance. In this wizard, you select source and target settings, validate prerequisites, and start continuous replication for the migration cutover path.

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-1.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-2.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-3.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-4.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-5.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-6.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-7.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-8.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-9.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-10.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-11.png)

![New Managed Instance link](../../Images/c3-step10.0-new-mi-link-12.png)

## Task: Check Azure SQL Managed Instance link status after failover

Review link status in SSMS and Azure to confirm the connection is healthy and replication is progressing from source to target. Validate with read checks and controlled data changes to ensure synchronized results, proving the link is ready for a safe planned failover.

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-1.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-2.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-3.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-4.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-5.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-6.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-7.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-8.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-9.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-10.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-11.png)

``` sql
SELECT *
FROM [Person].[Person]
WHERE BusinessEntityID = 1
```

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-12.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-13.png)

``` sql
UPDATE [Person].[Person]
SET FirstName = 'Rafa',
 LastName = 'Nadal'
WHERE BusinessEntityID = 1
```

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-14.png)

![Managed Instance link status](../../Images/c3-step11.0-mi-link-status-15.png)

## Task: Failover to Azure SQL Managed Instance

Execute a planned failover to switch primary role from SQL Server 2025 on the VM to Azure SQL Managed Instance. This step finalizes the migration path by making the managed instance writable while preserving data consistency through synchronized replication.

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-1.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-2.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-3.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-4.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-5.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-6.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-7.png)

![Failover to Azure SQL Managed Instance](../../Images/c3-step12.0-failover-8.png)

## Task: Check Azure SQL Managed Instance link status

After failover, verify that role status and replication direction reflect the new topology, with Azure SQL Managed Instance as primary. Confirm expected behavior in monitoring views to ensure the environment is stable before deciding whether to keep or remove the link.

![Managed Instance link status](../../Images/c3-step13.0-mi-link-status-1.png)

![Managed Instance link status](../../Images/c3-step13.0-mi-link-status-2.png)

![Managed Instance link status](../../Images/c3-step13.0-mi-link-status-3.png)

## Task: Remove Azure SQL Managed Instance link

Remove the SQL Managed Instance link when you are ready to make the cutover permanent. This decommissions replication artifacts and confirms that production now runs on Azure SQL Managed Instance, completing the one-way migration from the source SQL Server 2025 VM.

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-1.png)

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-2.png)

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-3.png)

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-4.png)

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-5.png)

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-6.png)

![Delete Azure SQL Managed Instance link](../../Images/c3-step14.0-delete-mi-link-7.png)

---

[Previous Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Next Solution](../challenge-04/solution-04.md)
