# Azure Monitor Logs FinOps Showcase

This repository is a beginner-friendly demo for Microsoft Azure Monitor Logs cost optimization.

It shows a practical FinOps approach:

1. Ingest less with DCR filtering and projection.
2. Use the right table tier (Analytics, Basic, Auxiliary path).
3. Control retention and long-term storage cost.
4. Keep guardrails with alerts and regular reviews.

## Start Here (10-minute flow)

```powershell
# 1) Deploy synthetic demo
.\quick-deploy.ps1 -NamePrefix "logoptdemo"

# 2) Load environment values
. .\.env.ps1

# 3) Send sample data
.\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180

# 4) Validate
.\run-demo-checks.ps1 -Timespan P1D
```

If validation returns zeros at first, wait a few minutes and run checks again.

## What You Learn in This Demo

1. DCR rules reduce ingestion volume before billing.
2. Basic and Auxiliary paths are used for lower-value or low-touch logs.
3. Analytics is kept for critical operational logs.
4. Retention and export are used for long-term cost control.

## Log Tiering (Simple)

| Tier | Use it for | Cost direction | Demo table |
|---|---|---|---|
| Analytics | Critical operations and frequent investigations | Highest | AppEvents_CL |
| Basic | Troubleshooting logs queried less often | Lower | DebugTraces_CL |
| Auxiliary | High-volume, low-touch telemetry | Lowest path when available | AuxSignals_CL pattern |

Quick decision rule:

1. Daily operational stream -> Analytics.
2. Occasional troubleshooting stream -> Basic.
3. Rarely used high-volume stream -> Auxiliary path.

## DCR Rules (Plain Language)

Think of each DCR as three actions:

1. Keep only useful records.
2. Shape records by removing low-value columns.
3. Route records to the right tier.

Demo implementation: [modules/dcr.bicep](modules/dcr.bicep)

## If You Already Have a Workspace

You can use this repo as a pattern library without rebuilding your environment.

1. Baseline current cost drivers.
2. Apply DCR optimization first.
3. Move selected streams to better tiers.
4. Validate for 1-2 weeks.
5. Roll out in waves.

Baseline query example:

```powershell
az monitor log-analytics query --workspace <workspace-id> --analytics-query "Usage | where TimeGenerated > ago(30d) | where IsBillable == true | summarize IngestedGB=round(sum(Quantity)/1024,2) by DataType | order by IngestedGB desc"
```

## Commitment Tier, Retention, and Governance

Use this order:

1. Optimize DCR and tiering first.
2. Collect 2-4 weeks of stable post-change usage.
3. Evaluate commitment tier based on steady usage.
4. Set retention by data value.
5. Export long-term data when needed.

Practical governance cadence:

1. Weekly: top billable tables and noisy streams.
2. Monthly: tier fit, retention fit, commitment right-sizing.
3. After each change: rerun validation.

## Auxiliary Table Note

Some tenants or regions may not allow Auxiliary table creation through ARM in this flow.

In that case, the demo uses an Auxiliary-ready fallback path on Basic so the architecture still works.

### Create Auxiliary Manually in Portal

1. Open Azure Portal -> Log Analytics workspace -> Tables.
2. Create a custom log table (DCR-based).
3. Set table plan to Auxiliary.
4. Example name: `AuxPortal_CL`.
5. Re-run deployment and route to that table:

```powershell
.\deploy.ps1 -ResourceGroupName "<existing-rg>" -Location "germanywestcentral" -AuxTableOverrideName "AuxPortal_CL" -DeployRealVmSource $false -DeployRealWindowsVmSource $false -DeployRealPaaSSources $false
```

6. Verify plan:

```powershell
az monitor log-analytics workspace table show -g "<existing-rg>" --workspace-name "<workspace-name>" -n AuxPortal_CL --query "{name:name,plan:plan}" -o table
```

Expected result: `plan` is `Auxiliary`.

## Useful Files

1. Deployment script: [deploy.ps1](deploy.ps1)
2. Quick deployment: [quick-deploy.ps1](quick-deploy.ps1)
3. Data generator: [send-sample-data.ps1](send-sample-data.ps1)
4. Validation script: [run-demo-checks.ps1](run-demo-checks.ps1)
5. Cost query pack: [queries/cost-analysis.kql](queries/cost-analysis.kql)
6. Demo visuals: [queries/demo-visuals.kql](queries/demo-visuals.kql)
7. DCR module: [modules/dcr.bicep](modules/dcr.bicep)
8. Table module: [modules/tables.bicep](modules/tables.bicep)

## Full Deployment (Optional)

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

## Microsoft Learn References

1. Azure Monitor Logs cost best practices:
   https://learn.microsoft.com/azure/azure-monitor/logs/best-practices-logs#cost-optimization
2. Cost optimization in Azure Monitor:
   https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost
3. Azure Monitor cost and usage:
   https://learn.microsoft.com/azure/azure-monitor/fundamentals/cost-usage
4. Logs cost calculations and options:
   https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs
5. Log Analytics table plans:
   https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
6. Basic Logs configuration:
   https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
7. Auxiliary custom table:
   https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary
8. DCR transformations and cost:
   https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations#cost-for-transformations
