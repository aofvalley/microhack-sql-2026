<#
    Runs on SQL VMs via az vm run-command invoke.
    Downloads AdventureWorks2019.bak and WideWorldImporters-Full.bak
    from Microsoft SQL Server Samples GitHub releases to C:\Lab\Backups\.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'RunCommand bootstrap script writes progress to console and log.')]
param()

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Write-Log {
    param([string]$msg)
    "$(Get-Date -Format 'HH:mm:ss') $msg" | Tee-Object -FilePath 'C:\Lab\download-dbs.log' -Append | Write-Host
}

New-Item -ItemType Directory -Path 'C:\Lab\Backups' -Force | Out-Null

$downloads = @(
    @{
        Name    = 'AdventureWorks2019.bak'
        Uri     = 'https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak'
        OutFile = 'C:\Lab\Backups\AdventureWorks2019.bak'
    },
    @{
        Name    = 'WideWorldImporters-Full.bak'
        Uri     = 'https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak'
        OutFile = 'C:\Lab\Backups\WideWorldImporters-Full.bak'
    }
)

foreach ($dl in $downloads) {
    if (Test-Path $dl.OutFile) {
        $existingSize = (Get-Item $dl.OutFile).Length
        Write-Log "Already present: $($dl.Name) ($([math]::Round($existingSize/1MB,1)) MB) - skipping"
        continue
    }
    Write-Log "Downloading $($dl.Name)..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $dl.Uri -OutFile $dl.OutFile -UseBasicParsing -TimeoutSec 600
        $size = (Get-Item $dl.OutFile).Length
        Write-Log "Downloaded: $($dl.Name) ($([math]::Round($size/1MB,1)) MB)"
    } catch {
        Write-Log "ERROR downloading $($dl.Name): $_"
        exit 1
    }
}

Write-Log "Sample database downloads complete"
