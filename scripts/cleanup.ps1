#Requires -Version 7.0
<#
    Deletes all resources created by deploy.ps1.
    Requires confirmation unless -Force is specified.
    Usage: .\cleanup.ps1 -ResourceGroup rg-sqlhack-microhack-2026
           .\cleanup.ps1 -ResourceGroup rg-sqlhack-microhack-2026 -Force
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive workshop script uses colored console output.')]
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rgInfo = az group show --name $ResourceGroup 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $rgInfo) {
    Write-Host "Resource group '$ResourceGroup' does not exist - nothing to delete." -ForegroundColor Yellow
    exit 0
}

$resourceCount = az resource list --resource-group $ResourceGroup --query 'length(@)' -o tsv

Write-Host "`n  Resource group : $ResourceGroup" -ForegroundColor Yellow
Write-Host "  Location       : $($rgInfo.location)"
Write-Host "  Resources      : $resourceCount resource(s)"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Type DELETE to confirm deletion of ALL resources in '$ResourceGroup'"
    if ($confirm -ne 'DELETE') {
        Write-Host "Cancelled." -ForegroundColor Cyan
        exit 0
    }
}

Write-Host "Deleting '$ResourceGroup' (async)..." -ForegroundColor Cyan
az group delete --name $ResourceGroup --yes --no-wait

Write-Host "Deletion queued. Monitor in Azure Portal under Resource Groups." -ForegroundColor Green
Write-Host "Note: SQL Managed Instance (if deployed) can take 30+ min to delete."
