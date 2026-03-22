# Azure Monitor Logs FinOps Showcase

This repository is a simple, practical guide to optimize Azure Monitor Logs costs with Microsoft best practices.

It focuses on four levers:

1. DCR filtering and transformation (ingest less).
2. Table tiering (Analytics, Basic, Auxiliary-ready path).
3. Retention and export (store smart).
4. Guardrails (daily cap, anomaly, noisy table alerts).

## Quick Start (Demo Environment)

```powershell
# Deploy synthetic demo
.\quick-deploy.ps1 -NamePrefix "logoptdemo"

# Load environment variables
. .\.env.ps1

# Send sample data
.\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180

# Verify
.\run-demo-checks.ps1 -Timespan P1D
```

## Already Have A Workspace? Start Here

You do not need to rebuild everything. Use this repo as a pattern library.

1. Baseline current cost drivers.
2. Apply DCR rules to reduce volume first.
3. Move selected streams to the right tier.
4. Validate for 1-2 weeks.
5. Roll out in waves.

Baseline example:

```powershell
az monitor log-analytics query --workspace <workspace-id> --analytics-query "Usage | where TimeGenerated > ago(30d) | where IsBillable == true | summarize IngestedGB=round(sum(Quantity)/1024,2) by DataType | order by IngestedGB desc"
```

Reference queries: [queries/cost-analysis.kql](queries/cost-analysis.kql)

## Tiering Made Simple

Use this decision model per stream:

- Analytics:
    - Frequent investigations, dashboards, rich analytics, critical operations.
- Basic:
    - Troubleshooting logs queried occasionally.
- Auxiliary:
    - Very high-volume, low-touch logs where lowest cost is priority.

Start small: migrate one or two streams first.

## DCR Rules Made Simple

Think of DCR rules as: Keep, Shape, Route.

1. Keep only useful events (for example Warning/Error/Critical).
2. Shape data by dropping large low-value columns.
3. Route streams to the right table tier.

Practical patterns in this repo:

- Actionable events to Analytics: AppEvents_CL
- Troubleshooting traces to Basic: DebugTraces_CL
- Low-touch stream to Auxiliary-ready path: AuxSignals_CL

Reference implementation: [modules/dcr.bicep](modules/dcr.bicep)

## Safe Rollout Pattern

1. Pilot DCR + tiering for one app/team.
2. Keep original flow during pilot.
3. Compare before/after ingestion, alert quality, and query usability.
4. Promote successful rules to shared baseline.
5. Expand by app-team waves.

Avoid these mistakes:

- Moving critical logs to low-cost tiers too early.
- Dropping columns without checking alerts/workbooks.
- Changing too many streams at once.

## Commitment Tier, Retention, and Export

Simple guidance:

1. Optimize DCR and tiering first.
2. Then evaluate commitment tier using stable post-optimization usage.
3. Use retention by data value class.
4. Export long-term data to storage with lifecycle policies.

Template references:

- [main.bicep](main.bicep)
- [modules/storage.bicep](modules/storage.bicep)

## What Gets Deployed In This Repo

- Log Analytics workspace (pricing, cap, retention)
- DCE + DCR with transformations
- Analytics + Basic + Auxiliary-ready stream path
- Storage export with lifecycle management
- Alert guardrails
- Optional real sources (Linux VM, Windows VM, Key Vault, Storage diagnostics)

## Verify Outcomes

Use these files:

- Validation script: [run-demo-checks.ps1](run-demo-checks.ps1)
- Demo visuals: [queries/demo-visuals.kql](queries/demo-visuals.kql)
- Cost analysis: [queries/cost-analysis.kql](queries/cost-analysis.kql)

Tip: If first validation returns zeros, wait a few minutes and rerun.

## Auxiliary Note

Some environments may restrict creating new Auxiliary tables via ARM.

- This repo falls back to an Auxiliary-ready path so the FinOps model still works.
- If an Auxiliary table already exists, deployment can reuse it.

## Full Deployment Option

```powershell
.\deploy.ps1 -ResourceGroupName "rg-lawopt-demo" -Location "germanywestcentral"
. .\.env.ps1
.\send-sample-data.ps1 -EventCount 200 -TraceCount 500 -AuxCount 400
.\run-demo-checks.ps1 -Timespan P1D
```

## Cleanup

```powershell
.\cleanup-demo.ps1 -Force
```

## Microsoft Learn

- Azure Monitor Logs cost best practices:
    - https://learn.microsoft.com/azure/azure-monitor/logs/best-practices-logs#cost-optimization
- Azure Monitor cost optimization:
    - https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost#azure-monitor-logs
- Log Analytics table plans:
    - https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
- Basic Logs configuration:
    - https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
- Auxiliary custom table:
    - https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary
- DCR transformations and cost:
    - https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations#cost-for-transformations
