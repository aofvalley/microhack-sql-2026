<#
    Runs on SQL VMs via az vm run-command invoke.
    Restores per-team databases from sample .bak files in C:\Lab\Backups\
    and sets the specified compatibility level.

    Parameters passed via --parameters in az vm run-command invoke:
      TeamCount   - int,    number of teams to create (1-based)
      CompatLevel - int,    110 (SQL2012-sim) or 130 (SQL2016-sim)
      SampleDb    - string, "AdventureWorks2019" or "WideWorldImporters"
      BackupFile  - string, filename inside C:\Lab\Backups\
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'RunCommand bootstrap script writes progress to console and log.')]
param(
    [int]    $TeamCount   = 1,
    [int]    $CompatLevel = 110,
    [string] $SampleDb    = 'AdventureWorks2019',
    [string] $BackupFile  = 'AdventureWorks2019.bak'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$msg)
    "$(Get-Date -Format 'HH:mm:ss') $msg" | Tee-Object -FilePath 'C:\Lab\setup-dbs.log' -Append | Write-Host
}

# Wait for SQL Server to be accepting connections
Write-Log "Checking SQL Server availability..."
$maxAttempts = 30
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Invoke-Sqlcmd -ServerInstance 'localhost' -Query 'SELECT 1' -TrustServerCertificate -ErrorAction Stop | Out-Null
        Write-Log "SQL Server is ready"
        break
    } catch {
        if ($attempt -eq $maxAttempts) { throw "SQL Server not available after $maxAttempts attempts" }
        Write-Log "Attempt $attempt/$maxAttempts - waiting 10s..."
        Start-Sleep -Seconds 10
    }
}

$backupPath = "C:\Lab\Backups\$BackupFile"
if (-not (Test-Path $backupPath)) {
    throw "Backup file not found: $backupPath - run download-sample-dbs.ps1 first"
}

# Read logical file names from the backup (needed for MOVE clauses)
Write-Log "Reading file list from $BackupFile..."
$fileList = Invoke-Sqlcmd -ServerInstance 'localhost' `
    -Query "RESTORE FILELISTONLY FROM DISK=N'$backupPath'" `
    -TrustServerCertificate

New-Item -ItemType Directory -Path 'C:\Lab\Data' -Force | Out-Null

for ($i = 1; $i -le $TeamCount; $i++) {
    $teamNum = '{0:D2}' -f $i
    $dbName  = "TEAM${teamNum}_${SampleDb}"

    $existing = Invoke-Sqlcmd -ServerInstance 'localhost' `
        -Query "SELECT state_desc FROM sys.databases WHERE name = N'$dbName'" `
        -TrustServerCertificate
    if ($existing -and $existing.state_desc -eq 'ONLINE') {
        Write-Log "Already ONLINE: $dbName - skipping"
        continue
    }

    # Build MOVE clauses with correct extensions for multiple data/log files
    $dataIdx   = 0
    $logIdx    = 0
    $moveParts = foreach ($file in $fileList) {
        if ($file.Type -eq 'D') {
            $ext = if ($dataIdx -eq 0) { '.mdf' } else { "_${dataIdx}.ndf" }
            $dataIdx++
        } else {
            $ext = if ($logIdx -eq 0) { '_log.ldf' } else { "_log${logIdx}.ldf" }
            $logIdx++
        }
        "MOVE N'$($file.LogicalName)' TO N'C:\Lab\Data\${dbName}${ext}'"
    }
    $moveClause = $moveParts -join ",`n     "

    $restoreQuery = @"
RESTORE DATABASE [$dbName]
FROM DISK = N'$backupPath'
WITH $moveClause,
     REPLACE, RECOVERY, STATS = 10;
ALTER DATABASE [$dbName] SET COMPATIBILITY_LEVEL = $CompatLevel;
"@

    Write-Log "Restoring $dbName (compat $CompatLevel)..."
    Invoke-Sqlcmd -ServerInstance 'localhost' -Query $restoreQuery `
        -TrustServerCertificate -QueryTimeout 600
    Write-Log "Done: $dbName"
}

Write-Log "setup-team-dbs complete - TeamCount=$TeamCount SampleDb=$SampleDb CompatLevel=$CompatLevel"
