// ============================================================================
// Storage Account for Data Export (Long-term Archive)
// ============================================================================

@description('Azure region')
param location string

@description('Unique suffix')
param suffix string

@description('Log Analytics workspace name')
param workspaceName string

var storageAccountName = 'stlawopt${suffix}'

// ============================================================================
// COST OPTIMIZATION #7: Data Export to Storage
//
// Export selected tables to blob storage for:
//   - Long-term retention beyond 12 years
//   - Cheaper storage (Cool/Archive tiers)
//   - Compliance & backup requirements
//   - Data accessible via ADX, Data Factory, or direct blob access
// ============================================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'  // Geo-redundant for cross-region backup
  }
  properties: {
    accessTier: 'Cool'     // Cool tier for infrequently accessed archive data
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// ============================================================================
// Lifecycle Management Policy
// Automatically move exported logs to Archive tier after 30 days
// ============================================================================
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'ArchiveOldLogs'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [ 'blockBlob' ]
              prefixMatch: [ 'am-' ]   // Azure Monitor export prefix
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 7
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 30
                }
                delete: {
                  daysAfterModificationGreaterThan: 730
                }
              }
            }
          }
        }
      ]
    }
  }
}

// ============================================================================
// Data Export Rule: Export SecurityEvent table to storage
// ============================================================================
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource dataExport 'Microsoft.OperationalInsights/workspaces/dataExports@2020-08-01' = {
  parent: workspace
  name: 'export-heartbeat'
  properties: {
    destination: {
      resourceId: storageAccount.id
    }
    tableNames: [
      'Heartbeat'
    ]
    enable: true
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
