<#
.SYNOPSIS
    Deploys the Azure Monitor Logs Cost Optimization demo environment.

.DESCRIPTION
    Deploys all resources for the Log Optimization demo:
    - Log Analytics Workspace (pricing tier, daily cap, retention)
    - Custom tables (Analytics vs Basic plan)
    - Data Collection Endpoint + Rules with transformations
    - Storage Account with lifecycle management for data export
    - Cost monitoring alert rules

.PARAMETER ResourceGroupName
    Name of the resource group to create/use.

.PARAMETER Location
    Azure region for deployment.

.PARAMETER PricingTier
    Log Analytics pricing tier: PerGB2018 or CapacityReservation.

.EXAMPLE
    .\deploy.ps1 -ResourceGroupName "rg-lawopt-demo" -Location "germanywestcentral"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-lawopt-demo",

    [Parameter(Mandatory = $false)]
    [string]$Location = "germanywestcentral",

    [Parameter(Mandatory = $false)]
    [ValidateSet("PerGB2018", "CapacityReservation")]
    [string]$PricingTier = "PerGB2018",

    [Parameter(Mandatory = $false)]
    [bool]$UseAuxiliaryPlan = $true
    ,
    [Parameter(Mandatory = $false)]
    [bool]$DeployRealVmSource = $true
    ,
    [Parameter(Mandatory = $false)]
    [bool]$DeployRealWindowsVmSource = $true
    ,
    [Parameter(Mandatory = $false)]
    [bool]$DeployRealPaaSSources = $true
    ,
    [Parameter(Mandatory = $false)]
    [string]$AuxTableOverrideName = ''
    ,
    [Parameter(Mandatory = $false)]
    [string]$VmAdminUsername = 'lawoptadmin'
    ,
    [Parameter(Mandatory = $false)]
    [string]$VmAdminPassword = ''
)

$ErrorActionPreference = "Stop"

$templateFilePath = Join-Path $PSScriptRoot 'main.bicep'
$envFilePath = Join-Path $PSScriptRoot '.env.ps1'

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Log Analytics Cost Optimization Demo" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($VmAdminPassword)) {
    $VmAdminPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 18 | ForEach-Object {[char]$_}) + '!aA1'
}

# ---- Check Azure CLI ----
Write-Host "[1/4] Checking Azure CLI login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

# ---- Create Resource Group ----
Write-Host "[2/4] Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none
Write-Host "  Resource group ready." -ForegroundColor Green

# ---- Optional: detect existing Auxiliary table and reuse it ----
$auxTableOverrideName = $AuxTableOverrideName
$effectiveUseAuxiliaryPlan = $UseAuxiliaryPlan
if ([string]::IsNullOrWhiteSpace($auxTableOverrideName)) {
    try {
        $existingWorkspaceName = az monitor log-analytics workspace list -g $ResourceGroupName --query "[0].name" -o tsv
        if (-not [string]::IsNullOrWhiteSpace($existingWorkspaceName)) {
            $auxTableOverrideName = az monitor log-analytics workspace table list -g $ResourceGroupName --workspace-name $existingWorkspaceName --query "[?plan=='Auxiliary'] | [0].name" -o tsv
        }
    } catch {
        # Non-blocking discovery.
    }
}

if (-not [string]::IsNullOrWhiteSpace($auxTableOverrideName)) {
    Write-Host "  Reusing Auxiliary table for low-touch DCR route: $auxTableOverrideName" -ForegroundColor Green
    Write-Host "  Skipping AuxSignals Auxiliary creation attempt to avoid ARM fallback noise." -ForegroundColor Gray
    $effectiveUseAuxiliaryPlan = $false
}

# ---- Deploy Bicep ----
Write-Host "[3/4] Deploying Bicep template..." -ForegroundColor Yellow
$deploymentName = "lawopt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$resultRaw = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "$templateFilePath" `
    --name $deploymentName `
    --parameters laPricingTier=$PricingTier enableAuxiliaryPlan=$effectiveUseAuxiliaryPlan auxTableOverrideName=$auxTableOverrideName deployRealVmSource=$DeployRealVmSource deployRealWindowsVmSource=$DeployRealWindowsVmSource deployRealPaaSSources=$DeployRealPaaSSources vmAdminUsername=$VmAdminUsername vmAdminPassword="$VmAdminPassword" `
    --query properties.outputs `
    --only-show-errors `
    --output json 2>&1

if ($LASTEXITCODE -ne 0 -and $UseAuxiliaryPlan -and ($resultRaw -match "Table plan 'Auxiliary' is not supported")) {
    Write-Host "  Auxiliary table creation via ARM is not available in this environment for new demo table AuxSignals_CL." -ForegroundColor Yellow
    Write-Host "  Typical reasons: region/cloud rollout differences, feature availability limits, or policy constraints on this subscription/tenant." -ForegroundColor Yellow
    Write-Host "  The script will continue with Basic fallback for AuxSignals_CL so the demo remains runnable." -ForegroundColor Yellow
    Write-Host "  If an existing Auxiliary table is already present (for example created in portal), it can still be detected and used." -ForegroundColor Yellow
    $deploymentName = "lawopt-$(Get-Date -Format 'yyyyMMdd-HHmmss')-fallback"
    $resultRaw = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "$templateFilePath" `
        --name $deploymentName `
        --parameters laPricingTier=$PricingTier enableAuxiliaryPlan=false auxTableOverrideName=$auxTableOverrideName deployRealVmSource=$DeployRealVmSource deployRealWindowsVmSource=$DeployRealWindowsVmSource deployRealPaaSSources=$DeployRealPaaSSources vmAdminUsername=$VmAdminUsername vmAdminPassword="$VmAdminPassword" `
        --query properties.outputs `
        --only-show-errors `
        --output json 2>&1
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Deployment failed!" -ForegroundColor Red
    Write-Host $resultRaw -ForegroundColor Red
    exit 1
}

$outputs = $resultRaw | ConvertFrom-Json
Write-Host "  Deployment succeeded!" -ForegroundColor Green

$detectedAuxTable = ''
if (-not [string]::IsNullOrWhiteSpace($auxTableOverrideName)) {
    $detectedAuxTable = $auxTableOverrideName
} else {
    try {
        $detectedAuxTable = az monitor log-analytics workspace table list -g $ResourceGroupName --workspace-name $outputs.workspaceName.value --query "[?plan=='Auxiliary'] | [0].name" -o tsv
    } catch {
        $detectedAuxTable = ''
    }
}

if ([string]::IsNullOrWhiteSpace($detectedAuxTable)) {
    $detectedAuxTable = 'AuxSignals_CL'
}

# ---- Print Outputs ----
Write-Host ""
Write-Host "[4/4] Deployment Outputs:" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Workspace Name     : $($outputs.workspaceName.value)" -ForegroundColor White
Write-Host "  Workspace ID       : $($outputs.workspaceCustomerId.value)" -ForegroundColor White
Write-Host "  DCE Endpoint       : $($outputs.dceEndpoint.value)" -ForegroundColor White
Write-Host "  DCR Analytics ID   : $($outputs.dcrAnalyticsImmutableId.value)" -ForegroundColor White
Write-Host "  DCR Basic ID       : $($outputs.dcrBasicImmutableId.value)" -ForegroundColor White
Write-Host "  DCR Aux-Fallback ID: $($outputs.dcrAuxFallbackImmutableId.value)" -ForegroundColor White
Write-Host "  Storage Account    : $($outputs.storageAccountName.value)" -ForegroundColor White
if ($outputs.PSObject.Properties.Name -contains 'realVmName' -and $outputs.realVmName.value) {
    Write-Host "  Real VM Name       : $($outputs.realVmName.value)" -ForegroundColor White
}
if ($outputs.PSObject.Properties.Name -contains 'realWindowsVmName' -and $outputs.realWindowsVmName.value) {
    Write-Host "  Real Windows VM    : $($outputs.realWindowsVmName.value)" -ForegroundColor White
}
if ($outputs.PSObject.Properties.Name -contains 'realKeyVaultName' -and $outputs.realKeyVaultName.value) {
    Write-Host "  Real Key Vault     : $($outputs.realKeyVaultName.value)" -ForegroundColor White
}
if ($outputs.PSObject.Properties.Name -contains 'realStorageName' -and $outputs.realStorageName.value) {
    Write-Host "  Real Storage       : $($outputs.realStorageName.value)" -ForegroundColor White
}
Write-Host "  Demo Auxiliary table: $detectedAuxTable" -ForegroundColor White

try {
    $auxTables = az monitor log-analytics workspace table list -g $ResourceGroupName --workspace-name $outputs.workspaceName.value --query "[?plan=='Auxiliary'].name" -o tsv
    if (-not [string]::IsNullOrWhiteSpace($auxTables)) {
        Write-Host "  Existing Auxiliary tables detected:" -ForegroundColor White
        foreach ($tbl in ($auxTables -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            Write-Host "    - $tbl" -ForegroundColor White
        }
    }
} catch {
    # Non-blocking informational check.
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---- Save outputs for data generator ----
$envFile = @"
`$env:DCE_ENDPOINT = "$($outputs.dceEndpoint.value)"
`$env:DCR_ANALYTICS_IMMUTABLE_ID = "$($outputs.dcrAnalyticsImmutableId.value)"
`$env:DCR_BASIC_IMMUTABLE_ID = "$($outputs.dcrBasicImmutableId.value)"
`$env:DCR_AUXILIARY_IMMUTABLE_ID = "$($outputs.dcrAuxFallbackImmutableId.value)"
`$env:WORKSPACE_NAME = "$($outputs.workspaceName.value)"
`$env:WORKSPACE_ID = "$($outputs.workspaceCustomerId.value)"
`$env:RESOURCE_GROUP = "$ResourceGroupName"
`$env:AUX_DEMO_TABLE = "$detectedAuxTable"
`$env:REAL_VM_NAME = "$($outputs.realVmName.value)"
`$env:REAL_WINDOWS_VM_NAME = "$($outputs.realWindowsVmName.value)"
`$env:REAL_KEYVAULT_NAME = "$($outputs.realKeyVaultName.value)"
`$env:REAL_STORAGE_NAME = "$($outputs.realStorageName.value)"
`$env:REAL_STORAGE_CONTAINER = "$($outputs.realStorageContainerName.value)"
"@
$envFile | Out-File -FilePath $envFilePath -Encoding utf8

# ---- Grant ingestion permissions on all DCRs for current signed-in user ----
Write-Host "Configuring DCR ingestion permissions..." -ForegroundColor Yellow
$userObjectId = az ad signed-in-user show --query id -o tsv
$dcrScopeIds = az resource list -g $ResourceGroupName --resource-type Microsoft.Insights/dataCollectionRules --query "[].id" -o tsv

foreach ($scopeId in $dcrScopeIds) {
    try {
        az role assignment create --assignee $userObjectId --role "Monitoring Metrics Publisher" --scope $scopeId --output none 2>$null
    } catch {
        # Ignore if already exists or transient lookup issue.
    }
}

Write-Host "Environment variables saved to .env.ps1" -ForegroundColor Green
Write-Host "Run: . .\.env.ps1  then  .\send-sample-data.ps1" -ForegroundColor Yellow
Write-Host ""
