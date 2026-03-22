param(
    [Parameter(Mandatory = $false)]
    [string]$NamePrefix = "logoptdemo",

    [Parameter(Mandatory = $false)]
    [string]$Location = "germanywestcentral",

    [Parameter(Mandatory = $false)]
    [bool]$UseAuxiliaryPlan = $true
    ,
    [Parameter(Mandatory = $false)]
    [string]$AuxTableOverrideName = ''
)

$ErrorActionPreference = "Stop"

$rand = -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
$resourceGroupName = "rg-$NamePrefix-$rand"

Write-Host "Quick deploy profile selected (synthetic-only)." -ForegroundColor Cyan
Write-Host "Resource group (isolated naming): $resourceGroupName" -ForegroundColor Cyan

& "$PSScriptRoot\deploy.ps1" `
    -ResourceGroupName $resourceGroupName `
    -Location $Location `
    -UseAuxiliaryPlan $UseAuxiliaryPlan `
    -AuxTableOverrideName $AuxTableOverrideName `
    -DeployRealVmSource $false `
    -DeployRealWindowsVmSource $false `
    -DeployRealPaaSSources $false

Write-Host "" 
Write-Host "Next steps (run one by one):" -ForegroundColor Yellow
Write-Host "  1) . .\\.env.ps1" -ForegroundColor White
Write-Host "  2) .\\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180" -ForegroundColor White
Write-Host "  3) .\\run-demo-checks.ps1 -Timespan P1D" -ForegroundColor White
Write-Host "  4) Optional cleanup (with confirmation): .\\cleanup-demo.ps1" -ForegroundColor White
Write-Host "     Use -Force only if you intentionally want non-interactive delete." -ForegroundColor Gray
