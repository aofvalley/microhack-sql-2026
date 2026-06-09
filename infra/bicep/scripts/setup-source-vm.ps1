param(
    [Parameter(Mandatory = $true)]
    [string]$SaPassword,

    [string]$SqlAdminLogin = 'sqladmin',

    [string]$SqlAdminPassword = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Prevent native command stderr / non-zero exits from auto-throwing under
# ErrorActionPreference=Stop (default $true in PowerShell 7.4+). sqlcmd writes
# RESTORE progress to stderr, which would otherwise terminate the script.
$PSNativeCommandUseErrorActionPreference = $false

$labRoot = 'C:\Lab'
$logPath = Join-Path $labRoot 'setup-source-vm.log'
$backupRoot = Join-Path $labRoot 'backups'
$sqlDataRoot = 'C:\SQLData'
$sqlInstance = 'MSSQLSERVER'
$serverName = 'localhost'

New-Item -Path $labRoot -ItemType Directory -Force | Out-Null
Start-Transcript -Path $logPath -Append -Force

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

function Invoke-BestEffort {
    param(
        [string]$Description,
        [scriptblock]$ScriptBlock
    )

    try {
        Write-Log $Description
        & $ScriptBlock
    }
    catch {
        Write-Log "$Description failed: $($_.Exception.Message)" 'WARN'
    }
}

function Test-TransientSqlError {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($Message)) { return $false }
    $patterns = @(
        'SHUTDOWN is in progress',
        'severe error occurred',
        'kill state',
        'not currently available',
        'is being recovered',
        'is starting up',
        'Login failed for user',
        'transport-level error',
        'semaphore timeout',
        'A network-related',
        'established connection',
        'Timeout expired',
        'No process is on the other end of the pipe',
        'pipe is being closed',
        'server was not found',
        # In-Memory OLTP (Hekaton): immediately after restoring a database with
        # memory-optimized data (e.g. WideWorldImporters), the initial full backup
        # can fail until the XTP checkpoint controller finishes recovering the
        # memory-optimized filegroup. These clear on their own within a minute or two.
        'Failed to create a backup file collection snapshot',
        'shared handle on physical db',
        'Msg 41389'
    )
    foreach ($pattern in $patterns) {
        if ($Message -match [regex]::Escape($pattern)) { return $true }
    }
    return $false
}

function Invoke-SqlAction {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$TimeoutMinutes = 12,
        [int]$DelaySeconds = 10
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $Action
        }
        catch {
            $message = $_.Exception.Message
            if ($null -ne $_.Exception.InnerException) {
                $message = "$message $($_.Exception.InnerException.Message)"
            }
            if ((Get-Date) -lt $deadline -and (Test-TransientSqlError -Message $message)) {
                Write-Log "Transient SQL error (attempt $attempt); retrying in $DelaySeconds s: $message" 'WARN'
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            throw
        }
    }
}

function ConvertTo-SqlLiteral {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) {
        return 'NULL'
    }

    return "N'$($Value.Replace("'", "''"))'"
}

function ConvertTo-SqlIdentifier {
    param([string]$Value)
    return "[$($Value.Replace(']', ']]'))]"
}

function Get-SqlConnection {
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$serverName;Database=master;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=60"
    $connection.Open()
    return $connection
}

function Invoke-SqlNonQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [int]$CommandTimeout = 0
    )

    Invoke-SqlAction -Action {
        $connection = Get-SqlConnection
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = $Query
            $command.CommandTimeout = $CommandTimeout
            [void]$command.ExecuteNonQuery()
        }
        finally {
            $connection.Dispose()
        }
    }
}

function Invoke-SqlScalar {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [int]$CommandTimeout = 0
    )

    Invoke-SqlAction -Action {
        $connection = Get-SqlConnection
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = $Query
            $command.CommandTimeout = $CommandTimeout
            return $command.ExecuteScalar()
        }
        finally {
            $connection.Dispose()
        }
    }
}

function Get-BackupFileList {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    Invoke-SqlAction -Action {
        $connection = Get-SqlConnection
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = "RESTORE FILELISTONLY FROM DISK = $(ConvertTo-SqlLiteral $BackupPath);"
            $command.CommandTimeout = 0
            $reader = $command.ExecuteReader()
            $files = @()
            while ($reader.Read()) {
                $files += [pscustomobject]@{
                    LogicalName  = [string]$reader['LogicalName']
                    PhysicalName = [string]$reader['PhysicalName']
                    Type         = [string]$reader['Type']
                }
            }
            $reader.Close()
            return $files
        }
        finally {
            $connection.Dispose()
        }
    }
}

function Get-SqlCmdPath {
    $command = Get-Command 'sqlcmd.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $searchRoots = @(
        'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC',
        'C:\Program Files\Microsoft SQL Server',
        'C:\Program Files (x86)\Microsoft SQL Server'
    )

    foreach ($root in $searchRoots) {
        if (Test-Path $root) {
            $match = Get-ChildItem -Path $root -Filter 'sqlcmd.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
    }

    throw 'sqlcmd.exe was not found. Install SQL Server command-line tools or ensure sqlcmd is in PATH.'
}

function Invoke-SqlCmdCli {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [int]$QueryTimeout = 0
    )

    $sqlcmd = Get-SqlCmdPath
    Invoke-SqlAction -Action {
        $arguments = @('-S', $serverName, '-E', '-b', '-t', [string]$QueryTimeout, '-Q', $Query)
        $output = & $sqlcmd @arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "sqlcmd failed with exit code $LASTEXITCODE. $($output -join [Environment]::NewLine)"
        }
        $output | ForEach-Object { Write-Host $_ }
    }
}

function Get-SqlInstanceId {
    $instanceNamesPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    $instanceNames = Get-ItemProperty -Path $instanceNamesPath -ErrorAction Stop
    $instanceId = $instanceNames.$sqlInstance
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        throw "SQL Server default instance '$sqlInstance' was not found in the registry."
    }

    return $instanceId
}

function Enable-SqlNetworkAndMixedMode {
    Write-Log 'Configuring SQL Server TCP/IP on port 1433 and mixed-mode authentication'
    $instanceId = Get-SqlInstanceId
    $basePath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"
    $tcpPath = Join-Path $basePath 'SuperSocketNetLib\Tcp'
    $ipAllPath = Join-Path $tcpPath 'IPAll'

    Set-ItemProperty -Path $basePath -Name 'LoginMode' -Type DWord -Value 2
    Set-ItemProperty -Path $tcpPath -Name 'Enabled' -Type DWord -Value 1
    Set-ItemProperty -Path $ipAllPath -Name 'TcpDynamicPorts' -Value ''
    Set-ItemProperty -Path $ipAllPath -Name 'TcpPort' -Value '1433'

    Get-ChildItem -Path $tcpPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like 'IP*' -and $_.PSChildName -ne 'IPAll' } |
        ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name 'Enabled' -Type DWord -Value 1 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name 'TcpDynamicPorts' -Value '' -ErrorAction SilentlyContinue
        }

    Write-Log 'Ensuring NT AUTHORITY\SYSTEM has sysadmin before applying configuration'
    Grant-SysadminToSystemIfNeeded

    Write-Log 'Restarting SQL Server service to apply configuration'
    $service = Get-Service -Name $sqlInstance
    if ($service.Status -ne 'Running') {
        Start-Service -Name $sqlInstance -ErrorAction Stop
    }
    else {
        Restart-Service -Name $sqlInstance -Force -ErrorAction Stop
    }
    Start-Service -Name 'SQLSERVERAGENT' -ErrorAction SilentlyContinue

    Wait-SqlOnline
}

function Grant-SysadminToSystemIfNeeded {
    # On the marketplace SQL image, only 'sa' is sysadmin and no Windows login
    # has sysadmin, so the CSE (running as NT AUTHORITY\SYSTEM) cannot configure
    # logins. Bootstrap by starting SQL in single-user mode (restricted to the
    # SQLCMD app), where a Local System connection is granted sysadmin, and add
    # NT AUTHORITY\SYSTEM to the sysadmin role permanently. Idempotent.
    $alreadySysadmin = $false
    try {
        $alreadySysadmin = ([int](Invoke-SqlScalar -Query "SELECT ISNULL(IS_SRVROLEMEMBER('sysadmin'), 0);" -CommandTimeout 15) -eq 1)
    }
    catch {
        $alreadySysadmin = $false
    }
    if ($alreadySysadmin) {
        Write-Log 'NT AUTHORITY\SYSTEM already has sysadmin; skipping bootstrap'
        return
    }

    Write-Log 'Granting sysadmin to NT AUTHORITY\SYSTEM via single-user mode'
    $sqlcmd = Get-SqlCmdPath

    Stop-Service -Name 'SQLSERVERAGENT' -Force -ErrorAction SilentlyContinue
    Stop-Service -Name $sqlInstance -Force -ErrorAction Stop
    Start-Sleep -Seconds 3

    $startOutput = & net start $sqlInstance /mSQLCMD 2>&1 | Out-String
    Write-Log "Single-user start output: $($startOutput.Trim())"

    $deadline = (Get-Date).AddMinutes(3)
    $ready = $false
    while (-not $ready -and (Get-Date) -lt $deadline) {
        & $sqlcmd -S $serverName -E -b -Q 'SELECT 1;' *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true } else { Start-Sleep -Seconds 3 }
    }
    if (-not $ready) {
        throw 'SQL Server did not become available in single-user mode.'
    }

    $grantQuery = "IF SUSER_ID('NT AUTHORITY\SYSTEM') IS NULL CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM];"
    $grantOutput = & $sqlcmd -S $serverName -E -b -Q $grantQuery 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to grant sysadmin in single-user mode (exit $LASTEXITCODE): $grantOutput"
    }

    Stop-Service -Name $sqlInstance -Force -ErrorAction Stop
    Start-Sleep -Seconds 3
    Write-Log 'Granted sysadmin to NT AUTHORITY\SYSTEM'
}

function Wait-SqlOnline {
    param(
        [int]$TimeoutMinutes = 15,
        [int]$RequiredConsecutiveSuccesses = 6,
        [int]$IntervalSeconds = 15
    )

    Write-Log "Waiting for SQL Server to be stable (need $RequiredConsecutiveSuccesses checks @ ${IntervalSeconds}s)"
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $consecutive = 0
    do {
        try {
            [void](Invoke-SqlAction -TimeoutMinutes 1 -DelaySeconds 5 -Action {
                $connection = Get-SqlConnection
                try {
                    $command = $connection.CreateCommand()
                    $command.CommandText = 'SELECT 1;'
                    $command.CommandTimeout = 15
                    return $command.ExecuteScalar()
                }
                finally {
                    $connection.Dispose()
                }
            })
            $consecutive++
            if ($consecutive -ge $RequiredConsecutiveSuccesses) {
                Write-Log "SQL Server is online and stable ($consecutive consecutive checks)"
                return
            }
            Start-Sleep -Seconds $IntervalSeconds
        }
        catch {
            $consecutive = 0
            if ((Get-Date) -gt $deadline) {
                throw 'Timed out waiting for SQL Server to come online and stabilize.'
            }
            Start-Sleep -Seconds $IntervalSeconds
        }
    } while ($true)
}

function Configure-SqlLogins {
    Write-Log 'Configuring SQL logins'

    # Preflight: confirm the CSE security context (NT AUTHORITY\SYSTEM) is a SQL
    # sysadmin before attempting privileged changes, so we fail fast with a clear
    # message instead of a cryptic "Cannot alter the login 'sa'" error.
    $context = Invoke-SqlScalar -Query "SELECT CONVERT(nvarchar(256), SYSTEM_USER) + N'|' + CONVERT(nvarchar(1), ISNULL(IS_SRVROLEMEMBER('sysadmin'), 0));"
    $contextParts = ([string]$context).Split('|')
    $loginName = $contextParts[0]
    $isSysadmin = if ($contextParts.Count -gt 1) { $contextParts[1] } else { '0' }
    Write-Log "SQL connection context: login='$loginName' sysadmin=$isSysadmin"
    if ($isSysadmin -ne '1') {
        throw "SQL connection context '$loginName' is not a sysadmin; cannot configure logins. Verify NT AUTHORITY\SYSTEM has sysadmin on this image."
    }

    $saPasswordLiteral = ConvertTo-SqlLiteral $SaPassword
    $query = @"
ALTER LOGIN [sa] ENABLE;
ALTER LOGIN [sa] WITH PASSWORD = $saPasswordLiteral UNLOCK, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
"@
    Invoke-SqlNonQuery -Query $query

    if (-not [string]::IsNullOrWhiteSpace($SqlAdminPassword) -and -not [string]::IsNullOrWhiteSpace($SqlAdminLogin)) {
        $adminLoginIdentifier = ConvertTo-SqlIdentifier $SqlAdminLogin
        $adminLoginLiteral = ConvertTo-SqlLiteral $SqlAdminLogin
        $adminPasswordLiteral = ConvertTo-SqlLiteral $SqlAdminPassword
        $adminQuery = @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = $adminLoginLiteral)
BEGIN
    CREATE LOGIN $adminLoginIdentifier WITH PASSWORD = $adminPasswordLiteral, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
END
ELSE
BEGIN
    ALTER LOGIN $adminLoginIdentifier WITH PASSWORD = $adminPasswordLiteral UNLOCK, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
    ALTER LOGIN $adminLoginIdentifier ENABLE;
END;
IF NOT EXISTS (
    SELECT 1
    FROM sys.server_role_members rm
    JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
    JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id
    WHERE r.name = N'sysadmin' AND m.name = $adminLoginLiteral
)
BEGIN
    ALTER SERVER ROLE [sysadmin] ADD MEMBER $adminLoginIdentifier;
END;
"@
        Invoke-SqlNonQuery -Query $adminQuery
        Write-Log "Configured SQL sysadmin login '$SqlAdminLogin'"
    }
    else {
        Write-Log 'No additional SQL admin login password was provided; skipping optional login creation'
    }
}

function Configure-Firewall {
    Write-Log 'Opening Windows Firewall for SQL Server TCP 1433'
    $ruleName = 'MicroHack SQL Server TCP 1433'
    # Idempotent: remove any existing rule and recreate, so re-runs do not hit
    # the unsupported Set-NetFirewallPortFilter -AssociatedNetFirewallRule path.
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433 | Out-Null
}

function Download-FileWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [int]$MaxAttempts = 5
    )

    if ((Test-Path $DestinationPath) -and ((Get-Item $DestinationPath).Length -gt 0)) {
        Write-Log "Download already exists: $DestinationPath"
        return
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Log "Downloading $Uri to $DestinationPath (attempt $attempt of $MaxAttempts)"
            Invoke-WebRequest -Uri $Uri -OutFile $DestinationPath -UseBasicParsing -TimeoutSec 1800
            if ((Test-Path $DestinationPath) -and ((Get-Item $DestinationPath).Length -gt 0)) {
                return
            }

            throw 'Downloaded file is missing or empty.'
        }
        catch {
            Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
            if ($attempt -eq $MaxAttempts) {
                throw
            }

            $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt) * 5)
            Write-Log "Download failed: $($_.Exception.Message). Retrying in $sleepSeconds seconds." 'WARN'
            Start-Sleep -Seconds $sleepSeconds
        }
    }
}

function Get-SafeSqlFileName {
    param([string]$Value)
    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    $safeName = $Value
    foreach ($character in $invalidCharacters) {
        $safeName = $safeName.Replace([string]$character, '_')
    }

    return $safeName.Replace(' ', '_')
}

function Restore-DatabaseFromBackup {
    param(
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [Parameter(Mandatory = $true)][string]$BackupPath
    )

    $databaseNameLiteral = ConvertTo-SqlLiteral $DatabaseName
    $databaseIdentifier = ConvertTo-SqlIdentifier $DatabaseName

    # Idempotency based on state, not mere existence. A previously interrupted
    # restore can leave the DB in RESTORING / RECOVERY_PENDING / SUSPECT, which
    # must not be treated as success. Only an ONLINE DB with tables is healthy.
    $state = [string](Invoke-SqlScalar -Query "SELECT state_desc FROM sys.databases WHERE name = $databaseNameLiteral;")
    if (-not [string]::IsNullOrWhiteSpace($state)) {
        if ($state -eq 'ONLINE') {
            $tableCount = [int](Invoke-SqlScalar -Query "SELECT CONVERT(int, COUNT(1)) FROM $databaseIdentifier.sys.tables;")
            if ($tableCount -gt 0) {
                Write-Log "Database '$DatabaseName' already restored and ONLINE ($tableCount tables); skipping restore"
                return
            }
            Write-Log "Database '$DatabaseName' is ONLINE but empty; recreating"
        }
        else {
            Write-Log "Database '$DatabaseName' exists in unhealthy state '$state'; dropping before restore"
        }

        $dropQuery = @"
IF DB_ID($databaseNameLiteral) IS NOT NULL
BEGIN
    BEGIN TRY
        ALTER DATABASE $databaseIdentifier SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    END TRY
    BEGIN CATCH
    END CATCH
    DROP DATABASE $databaseIdentifier;
END;
"@
        Invoke-SqlCmdCli -Query $dropQuery -QueryTimeout 0
    }

    Write-Log "Reading backup file list for $DatabaseName"
    $fileList = @(Get-BackupFileList -BackupPath $BackupPath)
    if ($fileList.Count -eq 0) {
        throw "Backup file list for '$BackupPath' is empty."
    }

    $moveClauses = New-Object System.Collections.Generic.List[string]
    $dataFileOrdinal = 0
    $logFileOrdinal = 0

    foreach ($file in $fileList) {
        $safeLogicalName = Get-SafeSqlFileName -Value $file.LogicalName
        switch ($file.Type) {
            'L' {
                $logFileOrdinal++
                $suffix = if ($logFileOrdinal -eq 1) { '_log.ldf' } else { "_log$logFileOrdinal.ldf" }
                $targetPath = Join-Path $sqlDataRoot "$DatabaseName$suffix"
            }
            default {
                $dataFileOrdinal++
                $extension = if ($dataFileOrdinal -eq 1) { '.mdf' } else { "_$dataFileOrdinal.ndf" }
                $targetPath = Join-Path $sqlDataRoot "$DatabaseName`_$safeLogicalName$extension"
            }
        }

        $moveClauses.Add("MOVE $(ConvertTo-SqlLiteral $file.LogicalName) TO $(ConvertTo-SqlLiteral $targetPath)")
    }

    $moveClauseText = $moveClauses -join ",`r`n    "
    $restoreQuery = @"
RESTORE DATABASE $databaseIdentifier
FROM DISK = $(ConvertTo-SqlLiteral $BackupPath)
WITH
    $moveClauseText,
    REPLACE,
    RECOVERY,
    STATS = 5;
"@

    Write-Log "Restoring database '$DatabaseName' from '$BackupPath'"
    Invoke-SqlCmdCli -Query $restoreQuery -QueryTimeout 0

    $finalState = [string](Invoke-SqlScalar -Query "SELECT state_desc FROM sys.databases WHERE name = $databaseNameLiteral;")
    if ($finalState -ne 'ONLINE') {
        throw "Database '$DatabaseName' is in state '$finalState' after restore; expected ONLINE."
    }
    Write-Log "Database '$DatabaseName' restored and ONLINE"
}

function Configure-DatabaseForMigration {
    param([Parameter(Mandatory = $true)][string]$DatabaseName)

    $databaseIdentifier = ConvertTo-SqlIdentifier $DatabaseName
    $backupPath = Join-Path $backupRoot "$DatabaseName-full.bak"
    $query = @"
ALTER DATABASE $databaseIdentifier SET RECOVERY FULL WITH NO_WAIT;
BACKUP DATABASE $databaseIdentifier
TO DISK = $(ConvertTo-SqlLiteral $backupPath)
WITH INIT, COMPRESSION, STATS = 5;
"@

    Write-Log "Setting '$DatabaseName' to FULL recovery and taking initial full backup"
    Invoke-SqlCmdCli -Query $query -QueryTimeout 0
}

function Install-ChocolateyIfMissing {
    $choco = Get-Command 'choco.exe' -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Log 'Chocolatey is already installed'
        return
    }

    Write-Log 'Installing Chocolatey'
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Test-Path 'C:\ProgramData\chocolatey\bin') {
        $env:Path += ';C:\ProgramData\chocolatey\bin'
    }
}

function Start-InstallerAndWait {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Name
    )

    Write-Log "Starting $Name installer"
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "$Name installer failed with exit code $($process.ExitCode)."
    }

    Write-Log "$Name installer completed with exit code $($process.ExitCode)"
}

function Install-ToolingDirect {
    Write-Log 'Installing tooling with direct downloads because Chocolatey is unavailable'

    Invoke-BestEffort -Description 'Installing SSMS with direct download' -ScriptBlock {
        $ssmsInstaller = Join-Path $labRoot 'SSMS-Setup.exe'
        Download-FileWithRetry -Uri 'https://aka.ms/ssmsfullsetup' -DestinationPath $ssmsInstaller
        Start-InstallerAndWait -FilePath $ssmsInstaller -ArgumentList @('/install', '/quiet', '/norestart') -Name 'SSMS'
    }

    Invoke-BestEffort -Description 'Installing Azure CLI with direct download' -ScriptBlock {
        $azureCliInstaller = Join-Path $labRoot 'AzureCLI.msi'
        Download-FileWithRetry -Uri 'https://aka.ms/installazurecliwindowsx64' -DestinationPath $azureCliInstaller
        Start-InstallerAndWait -FilePath 'msiexec.exe' -ArgumentList @('/i', $azureCliInstaller, '/quiet', '/qn', '/norestart') -Name 'Azure CLI'
    }

    Invoke-BestEffort -Description 'Installing Visual Studio Code with direct download' -ScriptBlock {
        $vscodeInstaller = Join-Path $labRoot 'VSCodeSetup.exe'
        Download-FileWithRetry -Uri 'https://update.code.visualstudio.com/latest/win32-x64/stable' -DestinationPath $vscodeInstaller
        Start-InstallerAndWait -FilePath $vscodeInstaller -ArgumentList @('/VERYSILENT', '/NORESTART', '/MERGETASKS=!runcode') -Name 'Visual Studio Code'
    }
}

function Install-LabTooling {
    Invoke-BestEffort -Description 'Installing Chocolatey if needed' -ScriptBlock {
        Install-ChocolateyIfMissing
    }

    $choco = Get-Command 'choco.exe' -ErrorAction SilentlyContinue
    if (-not $choco) {
        Install-ToolingDirect
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        if (Test-Path 'C:\Program Files\Microsoft VS Code\bin') {
            $env:Path += ';C:\Program Files\Microsoft VS Code\bin'
        }
        Install-VsCodeMssqlExtension
        return
    }

    Invoke-BestEffort -Description 'Installing SSMS, Azure CLI, and Visual Studio Code with Chocolatey' -ScriptBlock {
        & $choco.Source install -y ssms azure-cli vscode --no-progress
        if ($LASTEXITCODE -ne 0) {
            throw "choco install failed with exit code $LASTEXITCODE."
        }
    }

    Install-VsCodeMssqlExtension
}

function Install-VsCodeMssqlExtension {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Test-Path 'C:\Program Files\Microsoft VS Code\bin') {
        $env:Path += ';C:\Program Files\Microsoft VS Code\bin'
    }

    $codePath = $null
    $codeCommand = Get-Command 'code.cmd' -ErrorAction SilentlyContinue
    if ($codeCommand) {
        $codePath = $codeCommand.Source
    }
    elseif (Test-Path 'C:\Program Files\Microsoft VS Code\bin\code.cmd') {
        $codePath = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    }

    if ($codePath) {
        Invoke-BestEffort -Description 'Installing VS Code MSSQL extension' -ScriptBlock {
            & $codePath --install-extension ms-mssql.mssql --force
            if ($LASTEXITCODE -ne 0) {
                throw "VS Code extension install failed with exit code $LASTEXITCODE."
            }
        }
    }
    else {
        Write-Log 'VS Code command was not found; skipping MSSQL extension installation' 'WARN'
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($SaPassword)) {
        throw 'SaPassword is required.'
    }

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    New-Item -Path $sqlDataRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null

    Enable-SqlNetworkAndMixedMode
    Configure-SqlLogins
    Configure-Firewall

    $sampleDatabases = @(
        [pscustomobject]@{
            Name = 'AdventureWorks2019'
            Uri  = 'https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak'
            File = Join-Path $labRoot 'AdventureWorks2019.bak'
        },
        [pscustomobject]@{
            Name = 'WideWorldImporters'
            Uri  = 'https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak'
            File = Join-Path $labRoot 'WideWorldImporters-Full.bak'
        }
    )

    foreach ($database in $sampleDatabases) {
        Download-FileWithRetry -Uri $database.Uri -DestinationPath $database.File
    }

    Wait-SqlOnline

    foreach ($database in $sampleDatabases) {
        Restore-DatabaseFromBackup -DatabaseName $database.Name -BackupPath $database.File
        Configure-DatabaseForMigration -DatabaseName $database.Name
    }

    Install-LabTooling

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' MicroHack SQL 2026 source VM setup completed successfully. '
    Write-Host ' Databases: AdventureWorks2019, WideWorldImporters          '
    Write-Host " Log file: $logPath"
    Write-Host '============================================================'
    Write-Host ''
}
catch {
    Write-Log "Source VM setup failed: $($_.Exception.Message)" 'ERROR'

    Invoke-BestEffort -Description 'Dumping recent SQL Server ERRORLOG' -ScriptBlock {
        $logCandidates = @(
            Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Filter 'ERRORLOG' -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        )
        if ($logCandidates -and $logCandidates[0]) {
            Write-Host '----- SQL ERRORLOG (tail) -----'
            Get-Content -Path $logCandidates[0].FullName -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        }
    }

    Invoke-BestEffort -Description 'Dumping recent System event log entries' -ScriptBlock {
        Write-Host '----- System events (MSSQLSERVER / Service Control Manager) -----'
        Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddMinutes(-30) } -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'MSSQLSERVER|Service Control Manager|Microsoft-Windows-WindowsUpdateClient|User32' } |
            Select-Object -First 20 |
            ForEach-Object { Write-Host ("{0} [{1}] {2}" -f $_.TimeCreated, $_.ProviderName, ($_.Message -split "`n")[0]) }
    }

    throw
}
finally {
    Stop-Transcript
}
