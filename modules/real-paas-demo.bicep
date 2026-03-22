// ============================================================================
// Real PaaS Telemetry Demo
// Deploys Key Vault + Storage Account and sends diagnostics to Log Analytics
// ============================================================================

targetScope = 'resourceGroup'

@description('Azure region')
param location string

@description('Unique suffix for resource names')
param suffix string

@description('Log Analytics workspace resource ID')
param workspaceId string

var keyVaultName = 'kv-lawopt-${suffix}'
var storageName = toLower('stpaas${suffix}')

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    accessTier: 'Hot'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource demoContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'demo'
  properties: {
    publicAccess: 'None'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 7
    enableSoftDelete: true
  }
}

// Route Key Vault logs/metrics to LAW
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-keyvault-lawopt'
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Route Blob service logs/metrics to LAW
resource storageDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-storage-blob-lawopt'
  scope: blobService
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output storageName string = storage.name
output storageId string = storage.id
output storageContainerName string = demoContainer.name
