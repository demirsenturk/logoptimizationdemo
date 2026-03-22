// ============================================================================
// Cost Monitoring Alerts
// Proactive alerting for cost anomalies and budget protection
// ============================================================================

@description('Azure region')
param location string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Daily cap in GB')
param dailyCapGB int

// ============================================================================
// COST OPTIMIZATION #8: Proactive Cost Alerts
// ============================================================================

var capThreshold = dailyCapGB * 9 / 10   // 90% of daily cap

// Alert: Data ingestion exceeds 90% of daily cap
resource alertDailyCapWarning 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-ingestion-90pct-cap'
  location: location
  properties: {
    displayName: 'Ingestion approaching daily cap (90%)'
    description: 'Data ingestion has reached 90% of the daily cap. Investigate to avoid data loss when cap is hit.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT30M'
    windowSize: 'PT1H'
    scopes: [ workspaceId ]
    criteria: {
      allOf: [
        {
          query: 'Usage | where TimeGenerated > ago(1d) | where IsBillable == true | summarize IngestedGB = sum(Quantity) / 1000 | where IngestedGB > ${capThreshold}'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
  }
}

// Alert: Ingestion anomaly detection (spike > 2x average)
resource alertIngestionAnomaly 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-ingestion-anomaly'
  location: location
  properties: {
    displayName: 'Data ingestion anomaly detected'
    description: 'Daily ingestion exceeded 2x the 7-day average. Investigate for misconfigured sources or attacks.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [ workspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
            let avg7d = toscalar(
              Usage
              | where TimeGenerated between(ago(8d) .. ago(1d))
              | where IsBillable == true
              | summarize avg(Quantity) / 1000
            );
            Usage
            | where TimeGenerated > ago(1d)
            | where IsBillable == true
            | summarize TodayGB = sum(Quantity) / 1000
            | where TodayGB > avg7d * 2
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
  }
}

// Alert: Billable data per table (identify noisy tables)
resource alertNoisyTable 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-noisy-table'
  location: location
  properties: {
    displayName: 'Single table ingesting > 50% of total volume'
    description: 'A single table is ingesting more than 50% of total billable data. Review if this table needs filtering or Basic plan.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT6H'
    windowSize: 'P1D'
    scopes: [ workspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Usage
            | where TimeGenerated > ago(1d)
            | where IsBillable == true
            | summarize TableGB = sum(Quantity) / 1000 by DataType
            | extend TotalGB = toscalar(
                Usage
                | where TimeGenerated > ago(1d)
                | where IsBillable == true
                | summarize sum(Quantity) / 1000
              )
            | where TableGB > TotalGB * 0.5
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
  }
}
