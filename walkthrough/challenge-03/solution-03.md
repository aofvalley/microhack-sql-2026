# Solution 3 — Security on Azure SQL Managed Instance (2026 edition)

[Previous Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Finish](../../challenges/finish.md)

## What changed since the original

This 2026 edition keeps the intent of the original MicroHack challenge but updates the Azure portal paths, security branding, and recommended implementation choices:

- **Microsoft Defender for SQL** is now managed through **Microsoft Defender for Cloud**. The legacy name **Azure Defender for SQL** appears only in older documentation and screenshots.
- **Data Discovery & Classification** still labels sensitive columns, but the UI is now database-centric and the recommendation workflow is slightly different.
- **Vulnerability Assessment** supports **express configuration**, so the lab no longer requires a dedicated storage account just to store scan results.
- **Always Encrypted with secure enclaves** on Azure SQL Managed Instance is generally available and is included as a modern data-protection exercise.
- **Microsoft Entra ID authentication** and Microsoft Entra-only authentication are the recommended posture for production estates. SQL authentication is still useful for lab simulation and compatibility testing.
- **Audit logs** should be sent to Log Analytics so security teams can query and retain activity centrally.

The lab continues to use the resources created in the previous challenges, including the managed instance `sqlmi-microhack-2026`, the migrated AdventureWorks database, the jumpbox/VM used for SQL Server Management Studio (SSMS), and the resource group created for the MicroHack.

> **Screenshot note:** Alfonso will reproduce the steps and replace the placeholders below with screenshots. Keep each image path as written so the walkthrough remains portable.

---

## Step 1 — Data Discovery & Classification

Data Discovery & Classification helps discover, classify, label, and report sensitive data stored in the database. It is useful for privacy programs, compliance reviews, and security prioritization. It does **not** encrypt, mask, or block access by itself; it adds metadata that can be used by reporting, auditing, and governance processes.

1. Open the Azure portal and go to **SQL managed instances**.
2. Select the managed instance **`sqlmi-microhack-2026`**.
3. In the database list, open the migrated AdventureWorks database used by your team. If the lab used a team naming convention, use the database that corresponds to your team, for example `AdventureWorks`, `AdventureWorks2019`, or `TEAMXX_TenantDataDb`.
4. In the database menu, under **Security**, select **Data Discovery & Classification**.

![SQL MI database security menu](../../Images/c3-step-01-sql-mi-database-security-menu.png)

5. Review the **Overview** page. The database may show no saved classifications yet, but the service should display a banner or link indicating that classification recommendations are available.
6. Select the recommendations banner, for example **View recommendations** or **We have found columns with classification recommendations**.

![Data Discovery overview recommendations](../../Images/c3-step-02-data-discovery-overview-recommendations.png)

7. Review the recommendation list. On AdventureWorks you should see recommendations for common sensitive attributes such as names, national identifiers, email addresses, phone numbers, addresses, credit card data, or other personally identifiable information depending on the database version loaded in Challenge 1.
8. Select the recommendations that apply to the lab data. Include columns such as:
   - `Person.Person.FirstName`
   - `Person.Person.LastName`
   - `Person.EmailAddress.EmailAddress`
   - `Sales.CreditCard.CardNumber` or equivalent credit-card columns
   - Any national ID, SSN, phone, or address columns present in your restored sample database
9. Select **Accept selected recommendations**.
10. Select **Save** to persist the classifications.

![Classification recommendation list](../../Images/c3-step-03-classification-recommendation-list.png)

11. Return to the **Overview** tab and confirm that the dashboard now shows classified columns grouped by sensitivity label and information type.

![Accepted classification overview](../../Images/c3-step-04-accepted-classification-overview.png)

12. Add one manual classification so you understand how to tag a column that was not automatically recommended. Select **+ Add classification**.
13. Use the following values:

| Field | Value |
|---|---|
| Schema | `Person` |
| Table | `EmailAddress` |
| Column | `EmailAddress` |
| Information type | `Contact Info` or `Email` |
| Sensitivity label | `Confidential` |

14. Select **Add classification**, then select **Save**.

![Add custom email classification](../../Images/c3-step-05-add-custom-email-classification.png)

15. Optional validation from SSMS: connect to `sqlmi-microhack-2026` and run the following query in the lab database:

```sql
SELECT
    schema_name(o.schema_id) AS schema_name,
    o.name AS table_name,
    c.name AS column_name,
    sc.label,
    sc.information_type,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.all_columns AS c
    ON sc.major_id = c.object_id
   AND sc.minor_id = c.column_id
JOIN sys.objects AS o
    ON c.object_id = o.object_id
ORDER BY schema_name, table_name, column_name;
```

16. Confirm that the classifications appear in `sys.sensitivity_classifications`.

![Sensitivity classifications query](../../Images/c3-step-06-sensitivity-classifications-query.png)

> **Remember:** classification is a governance and metadata feature. It complements access control, encryption, auditing, and Defender alerts, but it is not a runtime access-control mechanism.

---

## Step 2 — Enable Microsoft Defender for SQL

Microsoft Defender for SQL is part of Microsoft Defender for Cloud. It provides advanced threat protection and vulnerability assessment for Azure SQL resources and SQL servers on machines. In this lab you enable the relevant database plan at the subscription level so the managed instance is protected consistently.

1. In the Azure portal, search for and open **Microsoft Defender for Cloud**.
2. In the left navigation, select **Environment settings**.
3. Select the subscription that contains `sqlmi-microhack-2026`.

![Defender for Cloud environment settings](../../Images/c3-step-07-defender-environment-settings.png)

4. Select **Defender plans**.
5. Locate the database-related plans. In the modern portal these are shown under the **Databases** plan family and may include SQL servers on machines and Azure SQL databases/servers.
6. Turn the relevant database plan **On**. For this lab, make sure Azure SQL resources are covered.
7. Select **Save**.

![Enable Defender database plans](../../Images/c3-step-08-enable-defender-database-plans.png)

8. Return to the SQL managed instance or database resource and open **Microsoft Defender for Cloud** from the resource **Security** section.
9. Confirm that the database is protected. It can take a few minutes for the status to refresh.

![SQL MI protected status](../../Images/c3-step-09-sql-mi-protected-status.png)

If the plan is already enabled by the lab owner or proctor, do not disable it. Just capture the protected status and continue.

---

## Step 3 — Vulnerability Assessment baseline

Vulnerability Assessment (VA) scans the database and related server configuration against SQL security best-practice rules. The goal of this step is to run an initial scan, understand the findings, and baseline the findings that are expected for the lab environment.

1. In **Microsoft Defender for Cloud**, go to **Recommendations**.
2. Search for **SQL servers should have vulnerability assessment configured**.
3. Open the recommendation and locate the resource for `sqlmi-microhack-2026`.

![VA recommendation in Defender for Cloud](../../Images/c3-step-10-va-recommendation-defender.png)

4. Select the affected SQL managed instance or database.
5. Choose **Configure** or **Fix**.
6. Use **Express configuration** when prompted. Express configuration is the recommended modern setup and does not require you to provide a storage account for the lab.
7. Save the configuration.

![VA express configuration](../../Images/c3-step-11-va-express-configuration.png)

8. Open the vulnerability assessment experience for the database. Depending on the portal blade, this may be under the database **Microsoft Defender for Cloud** page or directly under **Vulnerability Assessment**.
9. Select **Scan** to run a manual scan.
10. Wait for the scan to complete. It usually takes a few minutes.

![Run VA scan](../../Images/c3-step-12-run-va-scan.png)

11. Review the failed checks. Typical lab findings can include configuration items such as excessive permissions, database owners, disabled auditing, guest access, cross-database ownership chaining, or other legacy settings carried forward by the migration.
12. Open a representative finding, such as a finding that recommends disabling cross-database ownership chaining or reducing broad permissions.
13. Read the description, impact, query results, and remediation script.

![VA finding details](../../Images/c3-step-13-va-finding-details.png)

14. Decide whether the finding is a real risk to remediate or an expected lab condition to baseline. For example, if a legacy dependency is intentionally present for the MicroHack, baseline it and document why. For production, do not baseline findings without risk acceptance.
15. For an expected finding, choose **Approve as baseline** or **Add all results as baseline**.
16. Confirm the baseline change.

![Approve VA baseline](../../Images/c3-step-14-approve-va-baseline.png)

17. Run the scan again.
18. Confirm that approved baseline findings no longer appear as active failures, while unapproved findings remain visible.
19. Export or capture the scan result if your proctor wants evidence for the challenge.

![VA baseline rescan result](../../Images/c3-step-15-va-baseline-rescan-result.png)

A good lab outcome is not necessarily a perfect score. A good outcome is that you can explain each finding, identify which ones should be fixed, and baseline only those that are expected and justified.

---

## Step 4 — Advanced Threat Protection

Advanced Threat Protection in Microsoft Defender for SQL detects suspicious database activity such as potential SQL injection, unusual access patterns, brute-force attempts, or anomalous queries. In this step you intentionally generate a suspicious query pattern and then review the alert.

> **Important:** Run this only in the lab database. Do not run suspicious test patterns against customer, production, or shared corporate databases.

1. Open SSMS on the lab VM.
2. Connect to `sqlmi-microhack-2026` using a SQL authentication account provided by the lab. The query pattern is easier to identify when it resembles an application connection.
3. Open a new query window against the AdventureWorks database.
4. If needed, use **Query > Connection > Change Connection** and set an application name in **Additional Connection Parameters**:

```text
Application Name=microhack-webapp-sql-injection-test
```

![SSMS connection application name](../../Images/c3-step-16-ssms-connection-application-name.png)

5. Run the following simulated SQL injection pattern:

```sql
SELECT *
FROM Person.Person
WHERE LastName = '' OR '1' = '1' --';
```

If your AdventureWorks schema differs, use any simple table in the database and keep the suspicious predicate pattern.

6. Confirm that the query returns rows. The point is not the result set; the point is to generate a suspicious query shape.

![Run SQL injection simulation](../../Images/c3-step-17-run-sql-injection-simulation.png)

7. Wait about 5 minutes. Alerts can take longer, sometimes up to 10-15 minutes in a lab subscription.
8. In the Azure portal, open **Microsoft Defender for Cloud**.
9. Select **Security alerts**.
10. Filter by the SQL managed instance resource, by severity, or by the lab resource group.
11. Open the alert that indicates a potential SQL injection or suspicious database activity.

![Defender SQL injection alert list](../../Images/c3-step-18-defender-sql-injection-alert-list.png)

12. Review the alert detail page. Capture the alert name, affected resource, severity, description, evidence, MITRE ATT&CK mapping if shown, and recommended remediation steps.
13. If the portal provides an investigation graph or related entities, open it and capture the screen.

![Defender alert detail](../../Images/c3-step-19-defender-alert-detail.png)

14. Discuss what would be different in production:
    - The source application and principal should be identifiable.
    - Alerts should route to the security operations process.
    - Application code should use parameterized queries or stored procedures.
    - Repeated alerts should become an incident, not just a lab screenshot.

---

## Step 5 — Microsoft Entra authentication (recommended)

Microsoft Entra ID authentication avoids unnecessary SQL logins, enables centralized identity governance, and supports conditional access and group-based administration patterns. For Azure SQL Managed Instance, configure a Microsoft Entra administrator and create contained users in the database mapped to Microsoft Entra users or groups.

1. In the Azure portal, open the SQL managed instance **`sqlmi-microhack-2026`**.
2. Under **Settings** or **Security**, select **Microsoft Entra ID**.
3. Select **Set admin**.
4. Choose the lab administrator account or, preferably, a Microsoft Entra group created for SQL administrators.
5. Save the setting.

![Set Microsoft Entra admin](../../Images/c3-step-20-set-entra-admin.png)

6. Connect to the managed instance using SSMS or Azure Data Studio with **Microsoft Entra authentication**.
7. In the AdventureWorks database, create a contained database user mapped to a Microsoft Entra group. Replace the group name with the group provided by your lab tenant.

```sql
CREATE USER [sg-sqlmi-microhack-readers] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [sg-sqlmi-microhack-readers];
```

8. For a contributor group, grant only the minimum permissions needed for the lab:

```sql
CREATE USER [sg-sqlmi-microhack-contributors] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [sg-sqlmi-microhack-contributors];
ALTER ROLE db_datawriter ADD MEMBER [sg-sqlmi-microhack-contributors];
```

![Create Microsoft Entra contained users](../../Images/c3-step-21-create-entra-contained-users.png)

9. Validate the effective users and roles:

```sql
SELECT
    dp.name,
    dp.type_desc,
    rp.name AS role_name
FROM sys.database_role_members AS drm
JOIN sys.database_principals AS rp
    ON drm.role_principal_id = rp.principal_id
JOIN sys.database_principals AS dp
    ON drm.member_principal_id = dp.principal_id
WHERE dp.name LIKE 'sg-sqlmi-microhack%'
ORDER BY dp.name, rp.name;
```

10. Optional hardening: evaluate Microsoft Entra-only authentication for production workloads and apply Azure Policy to detect or deny SQL authentication where appropriate. Do not disable SQL authentication in the lab until you confirm the proctor does not require it for later steps.

![Validate Entra users and roles](../../Images/c3-step-22-validate-entra-users-and-roles.png)

---

## Step 6 — Transparent Data Encryption with customer-managed key

Azure SQL Managed Instance uses Transparent Data Encryption (TDE) to encrypt data at rest. By default, Microsoft-managed keys are used. In this step you review the customer-managed key pattern, where the TDE protector is stored in Azure Key Vault.

> **Lab safety:** Customer-managed TDE is powerful. If the key is disabled, deleted, or inaccessible, the database can become unavailable. In production, use purge protection, soft delete, tested access policies or RBAC, and operational runbooks before changing the protector.

1. Create or identify a Key Vault in the lab resource group, for example `kv-microhack-sql-2026`.
2. Confirm that **soft delete** and **purge protection** are enabled.
3. Create or import an RSA key to use as the TDE protector, for example `sqlmi-tde-cmk`.

![Key Vault TDE key](../../Images/c3-step-23-key-vault-tde-key.png)

4. Ensure the SQL managed instance identity can access the key. If the managed instance uses a system-assigned managed identity, grant that identity the required Key Vault permissions. With Azure RBAC, assign a role such as **Key Vault Crypto Service Encryption User** at the key or vault scope.
5. If the Key Vault firewall is enabled, allow trusted Microsoft services when appropriate and confirm the managed instance can reach the vault. In stricter environments, validate private endpoint and DNS configuration.

![Key Vault RBAC for SQL MI identity](../../Images/c3-step-24-key-vault-rbac-sql-mi-identity.png)

6. Open the SQL managed instance **`sqlmi-microhack-2026`**.
7. Go to **Transparent data encryption** or **Data encryption**.
8. Select **Customer-managed key**.
9. Choose the Key Vault and key `sqlmi-tde-cmk`.
10. Save the configuration and wait for the protector update to complete.

![Set TDE customer managed key](../../Images/c3-step-25-set-tde-customer-managed-key.png)

11. Validate the configured protector from the portal or with Azure CLI/PowerShell if available.
12. Record the key name, version, managed identity, and Key Vault configuration as evidence for the lab.

---

## Step 7 — Always Encrypted with secure enclaves

Always Encrypted protects sensitive data from high-privilege users who should manage the database but should not see protected values. Secure enclaves enable richer operations over encrypted columns by allowing protected computations inside a trusted enclave. Azure SQL Managed Instance supports Always Encrypted with secure enclaves using VBS enclaves.

For the lab, use a non-critical sensitive column such as `Person.EmailAddress.EmailAddress`. In a real modernization project, validate application compatibility, driver support, query patterns, indexing strategy, and key lifecycle before encrypting a column.

1. Confirm the managed instance supports secure enclaves and that the database compatibility level and client tooling are current.
2. Open SSMS with a recent version that supports Always Encrypted with secure enclaves.
3. Connect to `sqlmi-microhack-2026`.
4. Right-click the AdventureWorks database and choose **Tasks > Encrypt Columns**.

![SSMS encrypt columns wizard](../../Images/c3-step-26-ssms-encrypt-columns-wizard.png)

5. Select a sensitive column such as `Person.EmailAddress.EmailAddress`.
6. Choose deterministic or randomized encryption based on the operation you want to support. For a lab email address column, randomized encryption is usually safer unless equality searches are required.
7. Select or create a Column Master Key backed by Azure Key Vault.
8. Select or create a Column Encryption Key.
9. Enable enclave computations when prompted and use the VBS enclave option for Azure SQL Managed Instance.

![Always Encrypted enclave settings](../../Images/c3-step-27-always-encrypted-enclave-settings.png)

10. Review the generated script before applying changes. The wizard may generate `CREATE COLUMN MASTER KEY`, `CREATE COLUMN ENCRYPTION KEY`, and column encryption operations.
11. Apply the change during the lab window.
12. Test a query from a connection that is **not** configured with column encryption. The encrypted value should not be readable as plaintext.
13. Test again from a client configured with `Column Encryption Setting=Enabled` and the right key access. The value should be decrypted for authorized clients.

![Encrypted column query validation](../../Images/c3-step-28-encrypted-column-query-validation.png)

If the wizard is not available in your VM image, document the expected configuration and continue. The main learning outcome is understanding how Always Encrypted protects data from database operators and how secure enclaves expand supported operations.

---

## Step 8 — Audit logging

Auditing records database events and writes them to a destination such as Log Analytics, Storage, or Event Hubs. For this lab, send audit events to Log Analytics so they can be queried with KQL.

1. Open the SQL managed instance **`sqlmi-microhack-2026`** or the lab database.
2. Under **Security**, select **Auditing**.
3. Turn auditing **On**.
4. Choose **Log Analytics** as the destination.
5. Select the workspace used for the MicroHack, or create one if the lab does not already include it.
6. Save the configuration.

![Enable SQL MI auditing to Log Analytics](../../Images/c3-step-29-enable-sqlmi-auditing-log-analytics.png)

7. Generate a few audit events. For example, run a successful query and then attempt a failed login using an intentionally wrong password from SSMS.
8. Wait a few minutes for events to reach Log Analytics.
9. Open the Log Analytics workspace and run a query against SQL audit events:

```kusto
SQLSecurityAuditEvents
| where TimeGenerated > ago(2h)
| where LogicalServerName has "sqlmi-microhack-2026" or ServerInstanceName has "sqlmi-microhack-2026"
| project TimeGenerated, ActionName, Succeeded, ServerPrincipalName, DatabaseName, Statement, ClientIp, ApplicationName
| order by TimeGenerated desc
```

10. To focus on failed logins or failed actions, use:

```kusto
SQLSecurityAuditEvents
| where TimeGenerated > ago(2h)
| where Succeeded == false
| project TimeGenerated, ActionName, ServerPrincipalName, DatabaseName, Statement, ClientIp, ApplicationName
| order by TimeGenerated desc
```

![KQL SQL security audit events](../../Images/c3-step-30-kql-sql-security-audit-events.png)

11. Capture the query and results. Explain why centralized audit retention is important for incident response and compliance.

---

## Step 9 — Validate the security posture

The final step is to verify that the managed instance is visible in Defender for Cloud, that the VA baseline is understood, and that the security controls configured in the lab are producing evidence.

1. Open **Microsoft Defender for Cloud**.
2. Go to **Inventory** or **Security posture** and locate `sqlmi-microhack-2026`.
3. Review the resource recommendations, secure score contribution, and current alerts.

![Defender secure score SQL MI](../../Images/c3-step-31-defender-secure-score-sql-mi.png)

4. Re-run Vulnerability Assessment for the lab database.
5. Confirm that expected findings are covered by baseline and unexpected findings remain visible.
6. Confirm that Microsoft Defender for SQL is enabled.
7. Confirm that Data Discovery & Classification shows saved classifications.
8. Confirm that auditing is writing to Log Analytics.
9. If you completed the optional encryption steps, confirm the TDE protector and Always Encrypted configuration.

![Final SQL security posture summary](../../Images/c3-step-32-final-sql-security-posture-summary.png)

Use the following checklist as your completion evidence:

| Control | Expected evidence |
|---|---|
| Data Discovery & Classification | Sensitive AdventureWorks columns are labeled and visible in the portal |
| Microsoft Defender for SQL | Database plan enabled in Defender for Cloud |
| Vulnerability Assessment | Initial scan completed and justified baseline applied |
| Advanced Threat Protection | Suspicious query alert reviewed in Defender for Cloud |
| Microsoft Entra authentication | Microsoft Entra admin configured and contained group users created |
| TDE with customer-managed key | SQL MI protector points to a Key Vault key |
| Always Encrypted with secure enclaves | Sensitive column encrypted and tested from client connection |
| Auditing | SQL audit events visible in Log Analytics |

---

## Learning resources

- [Microsoft Defender for SQL overview](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-sql-introduction)
- [Data Discovery & Classification for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/data-discovery-and-classification-overview)
- [Vulnerability Assessment for Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-vulnerability-assessment)
- [Express configuration for SQL vulnerability assessment](https://learn.microsoft.com/en-us/azure/defender-for-cloud/sql-azure-vulnerability-assessment-overview)
- [Always Encrypted with secure enclaves](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-enclaves)
- [Always Encrypted with secure enclaves for Azure SQL Managed Instance](https://learn.microsoft.com/en-us/azure/azure-sql/database/always-encrypted-enclaves-getting-started)
- [Microsoft Entra authentication for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- [Configure and manage Microsoft Entra authentication with Azure SQL Managed Instance](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/aad-security-configure-tutorial)
- [Transparent Data Encryption with customer-managed key](https://learn.microsoft.com/en-us/azure/azure-sql/database/transparent-data-encryption-byok-overview)
- [Auditing for Azure SQL Database and Azure SQL Managed Instance](https://learn.microsoft.com/en-us/azure/azure-sql/database/auditing-overview)

---

[Previous Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Finish](../../challenges/finish.md)
