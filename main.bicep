// ============================================================================
// Azure Monitor Logs Cost Optimization Demo
// Deploys: LAW, DCR, DCE, Storage, Custom Tables, Data Export, Alerts
// ============================================================================

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = 'germanywestcentral'

@description('Unique suffix for resource names')
param suffix string = uniqueString(resourceGroup().id)

@description('Log Analytics pricing tier: PerGB2018 (pay-as-you-go) or commitment tier')
@allowed([
  'PerGB2018'
  'CapacityReservation'
])
param laPricingTier string = 'PerGB2018'

@description('Commitment tier in GB/day (100, 200, 300, 400, 500). Only used when laPricingTier = CapacityReservation')
@allowed([100, 200, 300, 400, 500])
param commitmentTierGBPerDay int = 100

@description('Interactive retention in days (31-730)')
@minValue(31)
@maxValue(730)
param interactiveRetentionDays int = 90

@description('Daily cap in GB. 0 = no cap')
param dailyCapGB int = 5

@description('Deploy AuxSignals_CL as true Auxiliary plan. If false, deploys as Basic fallback.')
param enableAuxiliaryPlan bool = true

@description('Optional existing table name to use for low-touch DCR routing (for example AuxPortal_CL).')
param auxTableOverrideName string = ''

@description('Deploy a real Linux VM source with AMA + DCR (adds cost).')
param deployRealVmSource bool = true

@description('Deploy a real Windows VM source with AMA + DCR (adds cost).')
param deployRealWindowsVmSource bool = true

@description('Deploy real PaaS sources (Key Vault + Storage diagnostics to LAW).')
param deployRealPaaSSources bool = true

@description('Admin username for real demo VM')
param vmAdminUsername string = 'lawoptadmin'

@secure()
@description('Admin password for real demo VM')
param vmAdminPassword string

// ============================================================================
// Module: Log Analytics Workspace
// ============================================================================
module workspace 'modules/workspace.bicep' = {
  name: 'workspace-deployment'
  params: {
    location: location
    suffix: suffix
    pricingTier: laPricingTier
    commitmentTierGBPerDay: commitmentTierGBPerDay
    interactiveRetentionDays: interactiveRetentionDays
    dailyCapGB: dailyCapGB
  }
}

// ============================================================================
// Module: Custom Tables with different plans (Analytics vs Basic + low-touch fallback)
// ============================================================================
module tables 'modules/tables.bicep' = {
  name: 'tables-deployment'
  params: {
    workspaceName: workspace.outputs.workspaceName
    enableAuxiliaryPlan: enableAuxiliaryPlan
  }
}

// ============================================================================
// Module: Data Collection Endpoint + Rules with transformations
// ============================================================================
module dcr 'modules/dcr.bicep' = {
  name: 'dcr-deployment'
  params: {
    location: location
    suffix: suffix
    workspaceId: workspace.outputs.workspaceId
    analyticsTableName: tables.outputs.analyticsTableName
    basicTableName: tables.outputs.basicTableName
    auxiliaryTableName: empty(auxTableOverrideName) ? tables.outputs.auxiliaryTableName : auxTableOverrideName
  }
}

// ============================================================================
// Module: Storage Account for Data Export (Archive tier)
// ============================================================================
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    suffix: suffix
    workspaceName: workspace.outputs.workspaceName
  }
}

// ============================================================================
// Module: Cost Monitoring Alerts
// ============================================================================
module alerts 'modules/alerts.bicep' = {
  name: 'alerts-deployment'
  params: {
    location: location
    workspaceId: workspace.outputs.workspaceId
    dailyCapGB: dailyCapGB
  }
}

// ============================================================================
// Module: Real VM source with AMA + DCR association
// ============================================================================
module realVm 'modules/real-vm-demo.bicep' = if (deployRealVmSource) {
  name: 'real-vm-source-deployment'
  params: {
    location: location
    suffix: suffix
    workspaceId: workspace.outputs.workspaceId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
  }
}

// ============================================================================
// Module: Real Windows VM source with AMA + DCR association
// ============================================================================
module realWindowsVm 'modules/real-windows-vm-demo.bicep' = if (deployRealWindowsVmSource) {
  name: 'real-windows-vm-source-deployment'
  params: {
    location: location
    suffix: suffix
    workspaceId: workspace.outputs.workspaceId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
  }
}

// ============================================================================
// Module: Real PaaS sources with diagnostics to workspace
// ============================================================================
module realPaaS 'modules/real-paas-demo.bicep' = if (deployRealPaaSSources) {
  name: 'real-paas-source-deployment'
  params: {
    location: location
    suffix: suffix
    workspaceId: workspace.outputs.workspaceId
  }
}

// ============================================================================
// Outputs
// ============================================================================
output workspaceName string = workspace.outputs.workspaceName
output workspaceId string = workspace.outputs.workspaceId
output workspaceCustomerId string = workspace.outputs.workspaceCustomerId
output dceEndpoint string = dcr.outputs.dceEndpoint
output dcrAnalyticsId string = dcr.outputs.dcrAnalyticsId
output dcrAnalyticsImmutableId string = dcr.outputs.dcrAnalyticsImmutableId
output dcrBasicId string = dcr.outputs.dcrBasicId
output dcrBasicImmutableId string = dcr.outputs.dcrBasicImmutableId
output dcrAuxFallbackId string = dcr.outputs.dcrAuxFallbackId
output dcrAuxFallbackImmutableId string = dcr.outputs.dcrAuxFallbackImmutableId
output storageAccountName string = storage.outputs.storageAccountName
output realVmName string = deployRealVmSource ? realVm!.outputs.vmName : ''
output realVmDcrId string = deployRealVmSource ? realVm!.outputs.vmDcrId : ''
output realWindowsVmName string = deployRealWindowsVmSource ? realWindowsVm!.outputs.vmName : ''
output realWindowsVmDcrId string = deployRealWindowsVmSource ? realWindowsVm!.outputs.vmDcrId : ''
output realKeyVaultName string = deployRealPaaSSources ? realPaaS!.outputs.keyVaultName : ''
output realStorageName string = deployRealPaaSSources ? realPaaS!.outputs.storageName : ''
output realStorageContainerName string = deployRealPaaSSources ? realPaaS!.outputs.storageContainerName : ''
