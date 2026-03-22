// ============================================================================
// Custom Tables: Analytics, Basic, and Auxiliary-candidate fallback
// Demonstrates cost difference between table plans
// ============================================================================

@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Use true Auxiliary plan for AuxSignals_CL table. If false, table uses Basic as fallback.')
param enableAuxiliaryPlan bool = true

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// ============================================================================
// COST OPTIMIZATION #4: Table Plans
//
// Analytics Plan (default):
//   - Full KQL query capabilities
//   - Alert rule support
//   - Higher ingestion cost
//   - Use for: operational data you query frequently
//
// Basic Plan:
//   - Lower ingestion cost (~67% cheaper)
//   - Limited query capabilities (no joins, summarize limited)
//   - Pay-per-query model
//   - Use for: debug/troubleshooting logs, verbose telemetry, audit trails
//
// Auxiliary-candidate fallback:
//   - In some environments, Auxiliary plan isn't enabled yet for table APIs.
//   - We keep a dedicated Basic table to model low-touch, high-volume logs.
// ============================================================================

// Table with ANALYTICS plan (full features, higher cost)
resource analyticsTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'AppEvents_CL'
  properties: {
    schema: {
      name: 'AppEvents_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime', description: 'Event timestamp' }
        { name: 'EventName', type: 'string', description: 'Name of the event' }
        { name: 'Severity', type: 'string', description: 'Event severity level' }
        { name: 'Message', type: 'string', description: 'Event message' }
        { name: 'UserId', type: 'string', description: 'User identifier' }
        { name: 'Duration', type: 'real', description: 'Operation duration in ms' }
        { name: 'ResourceId', type: 'string', description: 'Azure resource ID' }
      ]
    }
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 365
  }
}

// Table with BASIC plan (cheaper ingestion, limited query)
resource basicTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DebugTraces_CL'
  properties: {
    schema: {
      name: 'DebugTraces_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime', description: 'Event timestamp' }
        { name: 'TraceLevel', type: 'string', description: 'Trace level (Verbose/Debug/Info)' }
        { name: 'Component', type: 'string', description: 'Source component' }
        { name: 'Message', type: 'string', description: 'Trace message' }
        { name: 'CorrelationId', type: 'string', description: 'Correlation ID for tracing' }
      ]
    }
    plan: 'Basic'
    // Basic plan tables inherit workspace retention — custom retention not supported
  }
}

// Dedicated low-touch log stream table.
resource auxiliaryTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'AuxSignals_CL'
  properties: {
    schema: {
      name: 'AuxSignals_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime', description: 'Signal timestamp' }
        { name: 'SignalType', type: 'string', description: 'Signal category' }
        { name: 'SourceSystem', type: 'string', description: 'Source service/component' }
        { name: 'PayloadSizeBytes', type: 'int', description: 'Payload size in bytes' }
        { name: 'Message', type: 'string', description: 'Compact message' }
      ]
    }
    plan: enableAuxiliaryPlan ? 'Auxiliary' : 'Basic'
  }
}

output analyticsTableName string = analyticsTable.name
output basicTableName string = basicTable.name
output auxiliaryTableName string = auxiliaryTable.name
