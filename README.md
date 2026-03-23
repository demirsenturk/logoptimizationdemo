# Azure Monitor Logs FinOps Showcase

This repository is a beginner-friendly demo for Microsoft Azure Monitor Logs cost optimization.

It shows a practical FinOps approach:

1. Ingest less with DCR filtering and projection.
2. Use the right table tier (Analytics, Basic, Auxiliary path).
3. Control retention and long-term storage cost.
4. Keep guardrails with alerts and regular reviews.

## Start Here (10-minute flow)

```powershell
# 1) Clone repo and move into folder
git clone https://github.com/demirsenturk/logoptimizationdemo.git
cd logoptimizationdemo

# 2) Deploy synthetic demo
.\quick-deploy.ps1 -NamePrefix "logoptdemo"

# 3) Load environment values
. .\.env.ps1

# 4) Send sample data
.\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180

# 5) Validate
.\run-demo-checks.ps1 -Timespan P1D
```

If validation returns zeros at first, wait a few minutes and run checks again.
If you used `quick-deploy.ps1`, real VM/PaaS checks are skipped by design (synthetic-only profile).

<details>
<summary>Quick troubleshooting (expand)</summary>

If a command fails with `WorkspaceNotFoundError` or `No such host is known`:

1. Ensure you are inside the repo folder.
2. Re-run deployment to generate fresh environment values:

```powershell
.\quick-deploy.ps1 -NamePrefix "logoptdemo"
. .\.env.ps1
```

3. Wait 2-5 minutes for DCE DNS propagation, then run:

```powershell
.\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180
.\run-demo-checks.ps1 -Timespan P1D
```

</details>

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

### DCR Examples for Linux and Windows VMs

<details>
<summary>Expand DCR examples and references</summary>

Use these as learning templates for Azure Monitor Agent collection rules.

Linux VM example (Syslog to lower-cost table):

```bicep
resource dcrLinux 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
   name: 'dcr-linux-syslog'
   location: location
   properties: {
      dataSources: {
         syslog: [
            {
               name: 'linuxSyslog'
               streams: [ 'Microsoft-Syslog' ]
               facilityNames: [ 'auth', 'daemon', 'syslog' ]
               logLevels: [ 'Warning', 'Error', 'Critical' ]
            }
         ]
      }
      dataFlows: [
         {
            streams: [ 'Microsoft-Syslog' ]
            destinations: [ 'law' ]
            transformKql: 'source | where SeverityLevel <= 4 | project TimeGenerated, Computer, Facility, SeverityLevel, SyslogMessage'
            outputStream: 'Custom-DebugTraces_CL'
         }
      ]
   }
}
```

Windows VM example (Event logs with severity filter):

```bicep
resource dcrWindows 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
   name: 'dcr-windows-events'
   location: location
   properties: {
      dataSources: {
         windowsEventLogs: [
            {
               name: 'windowsEvents'
               streams: [ 'Microsoft-Event' ]
               xPathQueries: [
                  'System!*[System[(Level=1 or Level=2 or Level=3)]]'
                  'Application!*[System[(Level=1 or Level=2)]]'
               ]
            }
         ]
      }
      dataFlows: [
         {
            streams: [ 'Microsoft-Event' ]
            destinations: [ 'law' ]
            transformKql: 'source | project TimeGenerated, Computer, EventLog, EventLevelName, EventID, RenderedDescription'
            outputStream: 'Custom-AppEvents_CL'
         }
      ]
   }
}
```

References:

- Data Collection Rule overview: https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-rule-overview
- Azure Monitor Agent overview: https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-overview
- VM data collection with AMA and DCR: https://learn.microsoft.com/azure/azure-monitor/vm/data-collection

</details>

<details>
<summary>Advanced rollout and governance (expand)</summary>

## If You Already Have a Workspace

You can use this repo as a pattern library without rebuilding your environment.

1. Baseline current cost drivers.
2. Apply DCR optimization first.
3. Move selected streams to better tiers.
4. Validate for 1-2 weeks.
5. Roll out in waves.

Baseline query example:

```powershell
az monitor log-analytics query --workspace <workspace-id> --analytics-query "Usage | where TimeGenerated > ago(30d) | where IsBillable == true | summarize IngestedMB=round(sum(Quantity),2), IngestedGB=round(sum(Quantity)/1000,3) by DataType | order by IngestedMB desc"
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

</details>

## Auxiliary Table Note

Some tenants or regions may not allow Auxiliary table creation through ARM in this flow.

In that case, the demo uses an Auxiliary-ready fallback path on Basic so the architecture still works.

### Learn Auxiliary Logs (Microsoft Guidance)

<details>
<summary>Expand Auxiliary learning path and Microsoft links</summary>

If Auxiliary is not deployed automatically in your tenant, use this learning path:

1. Understand table plans and trade-offs.
2. Create a DCR-based custom table and set plan to Auxiliary.
3. Send a low-touch stream to that table through a DCR.
4. Validate the table plan and query behavior in Log Analytics.

Microsoft Learn links:

- Log Analytics table plans: https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
- Create custom table (Auxiliary): https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary
- Basic logs configuration (fallback pattern): https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
- DCR transformations: https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations

</details>

<details>
<summary>Known limitations and manual Auxiliary setup (expand)</summary>

## Known Limitations (Demo Context)

- Real VM and PaaS telemetry can take time to appear in some environments.
- Auxiliary table creation through ARM can be unavailable in some regions/tenants; Basic fallback is used automatically.
- Storage diagnostics warm-up can be affected by data-plane network/RBAC settings on the storage account.

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

</details>

<details>
<summary>Useful files and full deployment (expand)</summary>

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

</details>

## Cleanup

```powershell
.\cleanup-demo.ps1 -Force
```

## Microsoft Learn Quick Reference

Use this section as a fast lookup during deployment and demo prep.

Cost and FinOps guidance:

- Azure Monitor Logs cost optimization best practices: https://learn.microsoft.com/azure/azure-monitor/logs/best-practices-logs#cost-optimization
- Cost optimization in Azure Monitor (platform guidance): https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost
- Azure Monitor cost and usage: https://learn.microsoft.com/azure/azure-monitor/fundamentals/cost-usage
- Logs cost model and pricing options: https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs

Table plans and tiering:

- Log Analytics table plans (Analytics, Basic, Auxiliary): https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
- Basic Logs configuration: https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
- Create Auxiliary custom table: https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary

DCR and ingestion shaping:

- DCR transformations overview: https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations
- DCR transformation cost details: https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations#cost-for-transformations
