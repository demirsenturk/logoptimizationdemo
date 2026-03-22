param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = '',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    if (Test-Path "$PSScriptRoot\.env.ps1") {
        . "$PSScriptRoot\.env.ps1"
        if ($env:RESOURCE_GROUP) {
            $ResourceGroupName = $env:RESOURCE_GROUP
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw 'ResourceGroupName was not provided and could not be resolved from .env.ps1.'
}

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' Log Optimization Demo Cleanup' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "Target resource group: $ResourceGroupName" -ForegroundColor White

$rgExists = az group exists --name $ResourceGroupName -o tsv
if ($rgExists -ne 'true') {
    Write-Host 'Resource group does not exist. Nothing to clean up.' -ForegroundColor Yellow
    exit 0
}

if (-not $Force) {
    Write-Host 'This action will delete all resources in the group.' -ForegroundColor Yellow
    $confirm = Read-Host "Type DELETE to confirm removal of '$ResourceGroupName'"
    if ($confirm -ne 'DELETE') {
        Write-Host 'Cleanup cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

az group delete --name $ResourceGroupName --yes --no-wait --output none
Write-Host 'Cleanup initiated successfully.' -ForegroundColor Green
Write-Host "Use: az group show --name $ResourceGroupName" -ForegroundColor Gray
