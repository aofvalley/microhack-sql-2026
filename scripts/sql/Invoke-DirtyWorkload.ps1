<#
.SYNOPSIS
    Runs the dirty-workload.sql script against a SQL VM to generate Query Store data.
.PARAMETER TeamPrefix
    Team prefix in TEAM## format, e.g. TEAM01.
.PARAMETER SqlInstance
    SQL Server hostname or IP. Defaults to localhost.
.EXAMPLE
    .\Invoke-DirtyWorkload.ps1 -TeamPrefix TEAM01 -SqlInstance sqlhack-team-01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^TEAM\d{2}$')]
    [string]$TeamPrefix,

    [string]$SqlInstance = 'localhost'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sqlScript = Join-Path $scriptDir 'dirty-workload.sql'

if (-not (Test-Path $sqlScript)) {
    Write-Error "dirty-workload.sql not found at: $sqlScript"
    exit 1
}

Write-Host "Running dirty workload for $TeamPrefix on $SqlInstance..."

$result = sqlcmd -S $SqlInstance -E -v TeamPrefix=$TeamPrefix -i $sqlScript -b 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Error "sqlcmd exited with code $exitCode:`n$result"
    exit $exitCode
}

Write-Host "Dirty workload completed successfully for $TeamPrefix."
