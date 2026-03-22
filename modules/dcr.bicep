// ============================================================================
// Data Collection Endpoint + Data Collection Rules with Transformations
// Demonstrates ingestion-time cost optimization via DCR
// ============================================================================

@description('Azure region')
param location string

@description('Unique suffix')
param suffix string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Analytics table name')
param analyticsTableName string

@description('Basic table name')
param basicTableName string

@description('Auxiliary table name')
param auxiliaryTableName string

// ============================================================================
// Data Collection Endpoint
// ============================================================================
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: 'dce-costopt-${suffix}'
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ============================================================================
// COST OPTIMIZATION #5: DCR with Ingestion-Time Transformations
//
// DCR for Analytics table:
//   - FILTERS rows: Only ingest Severity Warning/Error/Critical (drop Info/Debug)
//   - PROJECTS columns: Drop verbose fields to reduce data volume
//   - Result: ~60-70% ingestion reduction on typical workloads
// ============================================================================
resource dcrAnalytics 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-analytics-${suffix}'
  location: location
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-AppEvents_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'EventName', type: 'string' }
          { name: 'Severity', type: 'string' }
          { name: 'Message', type: 'string' }
          { name: 'UserId', type: 'string' }
          { name: 'Duration', type: 'real' }
          { name: 'ResourceId', type: 'string' }
          { name: 'VerbosePayload', type: 'string' }
          { name: 'StackTrace', type: 'string' }
          { name: 'InternalDebugInfo', type: 'string' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'lawDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-AppEvents_CL' ]
        destinations: [ 'lawDestination' ]
        outputStream: 'Custom-${analyticsTableName}'
        // TRANSFORMATION BEST PRACTICES:
        // 1. Filter early to cut ingestion volume.
        // 2. Keep only business-relevant columns.
        // 3. Normalize types to reduce query-time parsing overhead.
        transformKql: 'source | where Severity in~ ("Warning", "Error", "Critical") | where isnotempty(EventName) and isnotempty(Message) | project TimeGenerated, EventName=tostring(EventName), Severity=tostring(Severity), Message=tostring(Message), UserId=tostring(UserId), Duration=toreal(Duration), ResourceId=tostring(ResourceId)'
      }
    ]
  }
}

// ============================================================================
// COST OPTIMIZATION #6: DCR for Basic Logs table
//
// Route verbose/debug data to the Basic plan table:
//   - Lower ingestion cost
//   - Ideal for troubleshooting data you rarely query
//   - Still accessible when needed (pay-per-query)
// ============================================================================
resource dcrBasic 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-basic-${suffix}'
  location: location
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-DebugTraces_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'TraceLevel', type: 'string' }
          { name: 'Component', type: 'string' }
          { name: 'Message', type: 'string' }
          { name: 'CorrelationId', type: 'string' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'lawDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-DebugTraces_CL' ]
        destinations: [ 'lawDestination' ]
        outputStream: 'Custom-${basicTableName}'
        // Keep Basic stream compact and clean while preserving troubleshooting value.
        transformKql: 'source | where isnotempty(Message) | project TimeGenerated, TraceLevel=tostring(TraceLevel), Component=tostring(Component), Message=tostring(Message), CorrelationId=tostring(CorrelationId)'
      }
    ]
  }
}

// ============================================================================
// COST OPTIMIZATION #7: DCR for auxiliary-candidate low-touch logs
//
// In this environment, Auxiliary plan is currently not available via ARM table API.
// This DCR routes a separate low-touch stream into a dedicated fallback table.
// ============================================================================
resource dcrAuxiliary 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-aux-${suffix}'
  location: location
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-AuxSignals_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'SignalType', type: 'string' }
          { name: 'SourceSystem', type: 'string' }
          { name: 'PayloadSizeBytes', type: 'int' }
          { name: 'Message', type: 'string' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'lawDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-AuxSignals_CL' ]
        destinations: [ 'lawDestination' ]
        outputStream: 'Custom-${auxiliaryTableName}'
        // Low-touch stream: keep minimal fields and sanitize payload size.
        transformKql: 'source | where isnotempty(SignalType) and isnotempty(SourceSystem) | project TimeGenerated, SignalType=tostring(SignalType), SourceSystem=tostring(SourceSystem), PayloadSizeBytes=iif(isnull(PayloadSizeBytes) or toint(PayloadSizeBytes) < 0, toint(0), toint(PayloadSizeBytes)), Message=tostring(Message)'
      }
    ]
  }
}


output dceEndpoint string = dce.properties.logsIngestion.endpoint
output dcrAnalyticsId string = dcrAnalytics.id
output dcrAnalyticsImmutableId string = dcrAnalytics.properties.immutableId
output dcrBasicId string = dcrBasic.id
output dcrBasicImmutableId string = dcrBasic.properties.immutableId
output dcrAuxFallbackId string = dcrAuxiliary.id
output dcrAuxFallbackImmutableId string = dcrAuxiliary.properties.immutableId
