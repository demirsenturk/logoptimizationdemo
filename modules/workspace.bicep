// ============================================================================
// Log Analytics Workspace with Cost Optimization Settings
// ============================================================================

@description('Azure region')
param location string

@description('Unique suffix')
param suffix string

@description('Pricing tier')
param pricingTier string

@description('Commitment tier GB/day')
param commitmentTierGBPerDay int

@description('Interactive retention days')
param interactiveRetentionDays int

@description('Daily ingestion cap in GB')
param dailyCapGB int

var workspaceName = 'law-costopt-${suffix}'

// ============================================================================
// COST OPTIMIZATION #1: Pricing Tier & Commitment Tier
// - Pay-as-you-go for < 100 GB/day
// - Commitment tiers for predictable high-volume ingestion (100+ GB/day)
// ============================================================================
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: pricingTier
      capacityReservationLevel: pricingTier == 'CapacityReservation' ? commitmentTierGBPerDay : null
    }

    // COST OPTIMIZATION #2: Retention Tiering
    // - Interactive retention: hot data, fully queryable (31-730 days)
    // - Archive/total retention: cold data, accessible via search jobs & restore (up to 12 years)
    retentionInDays: interactiveRetentionDays
    workspaceCapping: dailyCapGB > 0 ? {
      dailyQuotaGb: dailyCapGB
    } : null

    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ============================================================================
// COST OPTIMIZATION #3: Daily Cap
// - Prevents runaway ingestion costs
// - Set alerts at 90% threshold (handled in alerts module)
// ============================================================================
// Note: dailyCapGB is configured directly in the workspace properties above.

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
