param(
    [Parameter(Mandatory = $false)]
    [string]$NamePrefix = "logoptlab",

    [Parameter(Mandatory = $false)]
    [string]$Location = "germanywestcentral",

    [Parameter(Mandatory = $false)]
    [bool]$UseAuxiliaryPlan = $true
)

$ErrorActionPreference = "Stop"

$rand = -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
$resourceGroupName = "rg-$NamePrefix-$rand"

Write-Host "Quick deploy profile selected (synthetic-only)." -ForegroundColor Cyan
Write-Host "Resource group: $resourceGroupName" -ForegroundColor Cyan

& "$PSScriptRoot\deploy.ps1" `
    -ResourceGroupName $resourceGroupName `
    -Location $Location `
    -UseAuxiliaryPlan $UseAuxiliaryPlan `
    -DeployRealVmSource $false `
    -DeployRealWindowsVmSource $false `
    -DeployRealPaaSSources $false

Write-Host "" 
Write-Host "Next commands:" -ForegroundColor Yellow
Write-Host "  . .\\.env.ps1" -ForegroundColor White
Write-Host "  .\\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180" -ForegroundColor White
Write-Host "  .\\run-demo-checks.ps1 -Timespan P1D" -ForegroundColor White
