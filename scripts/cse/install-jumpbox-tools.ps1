#Requires -RunAsAdministrator
<#
    Runs on JumpBox VMs via az vm run-command invoke.
    Installs: SSMS 20, Azure CLI, Az PowerShell, SqlServer module, VS Code + MSSQL ext.
    Logs to C:\Lab\jumpbox-tools.log on the target VM.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Custom Script Extension writes progress to console and log.')]
param()

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$msg, [string]$level = 'INFO')
    $line = "$(Get-Date -Format 'HH:mm:ss') [$level] $msg"
    New-Item -ItemType Directory -Path 'C:\Lab' -Force | Out-Null
    $line | Tee-Object -FilePath 'C:\Lab\jumpbox-tools.log' -Append | Write-Host
}

function Invoke-Download {
    param([string]$Uri, [string]$OutFile)
    Write-Log "Downloading $(Split-Path $OutFile -Leaf)"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 600
        Write-Log "Downloaded: $(Split-Path $OutFile -Leaf)"
    } catch {
        Write-Log "Download failed for $OutFile : $_" 'WARN'
    }
}

New-Item -ItemType Directory -Path 'C:\Lab\Installers' -Force | Out-Null

# SSMS 20
$ssmsInstaller = 'C:\Lab\Installers\SSMS-Setup.exe'
if (-not (Test-Path $ssmsInstaller)) {
    Invoke-Download -Uri 'https://aka.ms/ssmsfullsetup' -OutFile $ssmsInstaller
}
if (Test-Path $ssmsInstaller) {
    Write-Log "Installing SSMS 20 (this takes ~10 min)..."
    Start-Process $ssmsInstaller -ArgumentList '/Install /Quiet /Norestart' -Wait -NoNewWindow
    Write-Log "SSMS install complete"
}

# Azure CLI
$azCliInstaller = 'C:\Lab\Installers\AzureCLI.msi'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Invoke-Download -Uri 'https://aka.ms/installazurecliwindows' -OutFile $azCliInstaller
    if (Test-Path $azCliInstaller) {
        Write-Log "Installing Azure CLI..."
        Start-Process msiexec.exe -ArgumentList "/i `"$azCliInstaller`" /qn /log C:\Lab\azcli-install.log" -Wait -NoNewWindow
        Write-Log "Azure CLI install complete"
    }
}

# Az and SqlServer PowerShell modules
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
foreach ($mod in @('Az', 'SqlServer')) {
    if (-not (Get-Module -Name $mod -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Log "Installing PowerShell module: $mod"
        Install-Module -Name $mod -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck
        Write-Log "$mod module installed"
    }
}

# VS Code
$vsCodeInstaller = 'C:\Lab\Installers\VSCodeSetup.exe'
if (-not (Test-Path 'C:\Program Files\Microsoft VS Code\Code.exe')) {
    Invoke-Download -Uri 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64' -OutFile $vsCodeInstaller
    if (Test-Path $vsCodeInstaller) {
        Write-Log "Installing VS Code..."
        Start-Process $vsCodeInstaller `
            -ArgumentList '/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath' `
            -Wait -NoNewWindow
        Write-Log "VS Code install complete"
    }
}

# VS Code MSSQL extension (best-effort; user can install manually if this fails)
$codeExe = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
if (Test-Path $codeExe) {
    Write-Log "Installing MSSQL extension for VS Code..."
    $env:PATH = "$env:PATH;C:\Program Files\Microsoft VS Code\bin"
    cmd /c "code --install-extension ms-mssql.mssql --force" 2>&1 | Out-Null
    Write-Log "MSSQL extension install attempted"
}

# Public desktop: lab info file
$desktopPath = 'C:\Users\Public\Desktop'
@"
=== SQL Modernization MicroHack 2026 ===

SQL Source VM A (SQL 2012 compat):  10.0.2.4,1433
SQL Source VM B (SQL 2016 compat):  10.0.2.5,1433

Your team databases: TEAMXX_AdventureWorks2019 and TEAMXX_WideWorldImporters
(XX = your team number, e.g. TEAM01)

SQL login: teamXX  (credentials shared by facilitator)

Challenges folder: see workshop chat for instructions PDF.
"@ | Out-File "$desktopPath\_SQLHACK_LAB_INFO.txt" -Encoding UTF8

Write-Log "JumpBox tools installation complete"
