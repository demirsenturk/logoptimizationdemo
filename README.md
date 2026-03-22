# Azure Monitor Logs FinOps Showcase Environment

This repository is a practical, customer-shareable showcase for Microsoft FinOps patterns on Azure Monitor Logs.

It demonstrates how to reduce logging costs while keeping operational visibility by combining:

- Data Collection Rules (DCR) transformation and filtering at ingestion time
- Table plan tiering (Analytics, Basic, and Auxiliary-ready routing)
- Retention and export strategy for long-term economics
- Commitment tier and daily cap governance decisions
- Alert-driven guardrails and KQL verification

Use this repo for a live session, a post-session customer handoff, or a self-paced lab.

## Who This Is For

- App teams that already have Log Analytics enabled and want to reduce cost without breaking operations
- Platform and SRE teams defining shared observability guardrails
- FinOps stakeholders who need a repeatable optimization model, not a one-time cleanup

## If You Already Have A Workspace (Enterprise Adoption Path)

If your team already runs production logging, use this repository as a pattern library instead of deploying a greenfield environment.

### Step 1: Baseline your current cost and usage

1. Identify top cost-driving tables by billable volume.
2. Separate high-value operational logs from verbose troubleshooting logs.
3. Document daily ingestion variability before any plan changes.

Example command:

```powershell
az monitor log-analytics query --workspace <workspace-id> --analytics-query "Usage | where TimeGenerated > ago(30d) | where IsBillable == true | summarize IngestedGB=round(sum(Quantity)/1024,2) by DataType | order by IngestedGB desc"
```

Use query patterns from [queries/cost-analysis.kql](queries/cost-analysis.kql).

### Step 2: Classify streams using a simple tier decision model

Use this rule of thumb for each stream:

- Analytics:
    - Use when data drives active investigations, dashboards, frequent alerting, or rich cross-table analytics.
- Basic:
    - Use when data is mainly for ad hoc troubleshooting and queried less frequently.
- Auxiliary:
    - Use for very high-volume, low-touch streams where low cost is more important than rich analytics.

Start by moving only one or two candidate streams. Avoid mass migration in the first iteration.

### Step 3: Apply DCR transformations before rerouting

Before changing table plans, reduce ingest volume with DCR transformations:

1. Filter out low-value events.
2. Project only required columns.
3. Normalize payload shape for compact ingestion.

Reference implementation: [modules/dcr.bicep](modules/dcr.bicep)

### DCR Rules Cookbook (Beginner Friendly)

Think about a DCR rule as a gate with three actions:

1. Keep: only keep records that are useful.
2. Shape: keep only columns needed for operations and investigations.
3. Route: send each stream to the right table plan.

#### Rule pattern A: Keep only actionable severities

- Goal: reduce noisy info/debug traffic.
- Example approach: keep Warning, Error, Critical and drop low-value informational rows.
- Typical target: Analytics table for high-value incidents.

#### Rule pattern B: Drop verbose payload columns

- Goal: reduce ingestion size per event.
- Example approach: remove large text blobs and internal debug payload columns.
- Typical target: same destination table, lower cost per record.

#### Rule pattern C: Route troubleshooting stream to Basic

- Goal: place less frequently queried logs in lower-cost tier.
- Example approach: send debug/trace stream into Basic table.
- Typical target: DebugTraces_CL in this repository pattern.

#### Rule pattern D: Route very high-volume low-touch stream to Auxiliary-ready path

- Goal: keep cost low for telemetry that is rarely explored interactively.
- Example approach: route compact stream to Auxiliary table when available, otherwise use fallback path.
- Typical target: AuxSignals_CL pattern in this repository.

### Safe Rollout Pattern For DCR Rule Changes

Use this operational sequence in existing production workspaces:

1. Clone one current stream into a pilot DCR flow for a single app or namespace.
2. Keep original stream unchanged during pilot window.
3. Compare for 7-14 days:
    - ingestion volume
    - alert fidelity
    - investigation usability
4. If results are good, promote rule to shared DCR baseline.
5. Roll out in waves by app team instead of a big-bang change.

### DCR Anti-Patterns To Avoid

- Moving critical operational logs to cheap tiers before validating incident workflows.
- Dropping columns without checking existing workbooks and alerts.
- Changing many streams at once, making impact hard to isolate.
- Evaluating commitment tiers before DCR and tiering are stabilized.

### Step 4: Pilot in one app or one namespace

1. Route one stream to Basic and one low-touch stream to Auxiliary-ready path.
2. Keep high-value stream in Analytics.
3. Compare 7-14 days before/after for ingestion, query success, and alert quality.

### Step 5: Scale with governance

1. Add daily cap and anomaly/noise alerts.
2. Review retention by data value, not by default settings.
3. Re-evaluate commitment tier only after DCR + tiering stabilize.

Guardrail references:

- [modules/alerts.bicep](modules/alerts.bicep)
- [run-demo-checks.ps1](run-demo-checks.ps1)

## Auxiliary Logs Explained For Beginners

Auxiliary is best understood as a low-cost lane for logs you rarely inspect.

- It is useful for high-volume telemetry where occasional retrieval is enough.
- It is not the first choice for your most interactive operational datasets.
- In some environments, creating new Auxiliary tables via ARM can be restricted.
- This repository handles that by falling back to an Auxiliary-ready Basic path so the operating model is still demonstrated.

For production teams, this means you can start optimizing now, even if true Auxiliary provisioning is currently constrained in your tenant or region.

## Business Outcomes

By the end of the walkthrough, customers can implement:

1. Ingest less data without losing high-value signals.
2. Route each log stream to the most cost-effective table plan.
3. Control retention spend with hot/warm/cold strategy.
4. Estimate run-rate and validate improvements with KQL.
5. Apply a repeatable operating model aligned to Microsoft guidance.

## What This Environment Deploys

| Capability | What is deployed | Why it matters for FinOps |
|---|---|---|
| Cost-aware workspace | Log Analytics workspace with pricing tier, cap, retention | Core cost control surface |
| DCR optimization | DCE + DCR streams with transformations | Reduce billable ingestion volume |
| Tiered tables | Analytics + Basic + Auxiliary-ready stream path | Match cost to query/access pattern |
| Long-term storage | Storage account + export + lifecycle | Lower long-horizon retention cost |
| Guardrails | Alert rules for cap/noise/anomaly | Keep optimization stable over time |
| Real telemetry option | Linux VM, Windows VM, Key Vault, Storage diagnostics | Prove patterns beyond synthetic data |

## Architecture Map

- High-value operational events -> DCR transform -> Analytics table AppEvents_CL
- Troubleshooting traces -> DCR route -> Basic table DebugTraces_CL
- Low-touch high-volume stream -> DCR route -> Auxiliary-ready path (AuxSignals_CL by default)
- Workspace usage and table costs -> KQL dashboards and checks
- Long-term data needs -> Export to blob + lifecycle to cool/archive

## Microsoft Best-Practice Patterns Showcased

### 1) Ingestion-Time Optimization with DCR

- Keep only required severity and columns before ingestion.
- Normalize payload structure to avoid unnecessary verbose fields.
- Use separate DCR streams for different data value profiles.

Implementation reference: [modules/dcr.bicep](modules/dcr.bicep)

### 2) Table Plan Tiering Strategy

| Table | Plan | Pattern |
|---|---|---|
| AppEvents_CL | Analytics | High-value ops, richer query needs |
| DebugTraces_CL | Basic | Lower-frequency troubleshooting |
| AuxSignals_CL or existing Auxiliary table | Auxiliary-ready | High-volume low-touch telemetry |

Implementation reference: [modules/tables.bicep](modules/tables.bicep)

### 3) Retention and Export Tiering

- Use workspace/table retention for hot operational window.
- Export selected data for long-term lower-cost storage.
- Apply lifecycle transitions to control storage cost over time.

Implementation reference: [modules/storage.bicep](modules/storage.bicep)

### 4) Cost Guardrails and Governance

- Daily cap usage visibility and alerting.
- Noisy table detection and anomaly-focused checks.
- Reusable KQL checks for post-change validation.

Implementation references:
- [modules/alerts.bicep](modules/alerts.bicep)
- [queries/cost-analysis.kql](queries/cost-analysis.kql)
- [run-demo-checks.ps1](run-demo-checks.ps1)

## Commitment Tier and Pricing Guidance

Use this environment to discuss when to move from pay-as-you-go to commitment tiers:

1. Start with PerGB2018 for new workloads and learning phases.
2. Measure stable daily ingestion over at least 2-4 weeks.
3. Compare observed daily usage against commitment break-even points.
4. Revisit after DCR filtering and tiering changes, not before.

Parameters are exposed in deployment to support this conversation:

- laPricingTier
- dailyCapGB
- interactiveRetentionDays

Template reference: [main.bicep](main.bicep)

## Migration Checklist For Existing Teams

Use this checklist when adopting patterns from this repository in an existing workspace:

1. Baseline last 30 days ingestion and top tables.
2. Select candidate streams for Basic or Auxiliary-ready routing.
3. Implement DCR filter and projection first.
4. Pilot on limited scope and validate alert/dashboard impact.
5. Apply retention and export policy by data value class.
6. Add cap and anomaly guardrails.
7. Revisit commitment tier decision with post-optimization data.
8. Roll out to additional app teams in waves.

## Prerequisites

- Azure subscription with rights for resource group deployment and role assignment
- Azure CLI and PowerShell 7
- Authenticated CLI session using az login
- For full mode: enough quota for Linux and Windows demo VMs in the chosen region

## Quick Start (Recommended for Sessions)

### Fast Synthetic Path

```powershell
# 1) Deploy synthetic-only stack into a new isolated resource group
.\quick-deploy.ps1 -NamePrefix "logoptdemo"

# 2) Load generated environment variables
. .\.env.ps1

# 3) Seed deterministic sample data
.\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180

# 4) Validate health, table plans, and ingestion outcomes
.\run-demo-checks.ps1 -Timespan P1D
```

### Full Real-Source Path

```powershell
# Deploy complete environment including Linux/Windows VM and PaaS sources
.\deploy.ps1 -ResourceGroupName "rg-lawopt-demo" -Location "germanywestcentral"

# Load env and seed data
. .\.env.ps1
.\send-sample-data.ps1 -EventCount 200 -TraceCount 500 -AuxCount 400

# Verify synthetic + real source checks
.\run-demo-checks.ps1 -Timespan P1D
```

Deployment script references:

- [quick-deploy.ps1](quick-deploy.ps1)
- [deploy.ps1](deploy.ps1)

## How to Validate FinOps Outcomes

Use these in order:

1. Run [run-demo-checks.ps1](run-demo-checks.ps1) and confirm data counts by stream.
2. Open [queries/demo-visuals.kql](queries/demo-visuals.kql) and run:
     - VISUAL 1: Cost by table
     - VISUAL 3: Severity mix after DCR filtering
     - VISUAL 4: Stream volume by plan path
     - VISUAL 6: Monthly run-rate by plan
3. Open [queries/cost-analysis.kql](queries/cost-analysis.kql) for deeper cost reasoning.

Tip: ingestion can take a few minutes. If first check returns zeros, wait and rerun.

## 15-Minute Customer Storyline

1. Cost baseline: show table-level usage and run-rate.
2. DCR optimization: show filter/project impact on AppEvents stream.
3. Plan tiering: explain Analytics vs Basic vs Auxiliary-ready strategy.
4. Retention/export: show workspace retention plus data export lifecycle.
5. Guardrails: show alerts and ongoing governance model.

Speaker guide reference: [DEMO-SCRIPT.md](DEMO-SCRIPT.md)

## Auxiliary Plan Behavior (Important)

This environment is designed to be robust across subscriptions:

- If Auxiliary creation is available, you can route low-touch stream to an Auxiliary table.
- If Auxiliary creation is blocked in your environment, deployment automatically falls back so demo flow still works.
- If a workspace already contains an Auxiliary table (for example AuxPortal_CL), the deployment can reuse it.

To force existing Auxiliary table usage in a second pass:

```powershell
.\deploy.ps1 -ResourceGroupName "<existing-rg>" -Location "germanywestcentral" -AuxTableOverrideName "AuxPortal_CL" -DeployRealVmSource $false -DeployRealWindowsVmSource $false -DeployRealPaaSSources $false
```

## Deployment Modes

- Full mode:
    - DeployRealVmSource true
    - DeployRealWindowsVmSource true
    - DeployRealPaaSSources true
    - Best for production-like observability proof
- Lightweight mode:
    - DeployRealVmSource false
    - DeployRealWindowsVmSource false
    - DeployRealPaaSSources false
    - Best for rapid workshop setup

## Customer Self-Paced Lab Path

After your session, customers can follow this exact flow:

1. Clone and run quick start.
2. Verify ingestion and table plan behavior.
3. Run KQL visuals and record before/after cost view.
4. Adjust event volumes and rerun checks.
5. Test retention and export assumptions for their own policy targets.

Cloud Shell instructions: [docs/CLOUD-SHELL-TEST.md](docs/CLOUD-SHELL-TEST.md)

## Repository Map

```text
.
|-- main.bicep
|-- main.bicepparam
|-- deploy.ps1
|-- quick-deploy.ps1
|-- send-sample-data.ps1
|-- run-demo-checks.ps1
|-- cleanup-demo.ps1
|-- DEMO-SCRIPT.md
|-- docs/
|   `-- CLOUD-SHELL-TEST.md
|-- modules/
|   |-- workspace.bicep
|   |-- tables.bicep
|   |-- dcr.bicep
|   |-- storage.bicep
|   |-- alerts.bicep
|   |-- real-vm-demo.bicep
|   |-- real-windows-vm-demo.bicep
|   `-- real-paas-demo.bicep
`-- queries/
        |-- cost-analysis.kql
        |-- demo-visuals.kql
        `-- verify-and-cleanup.kql
```

## Security and Operational Notes

- Generated runtime values are stored in local .env.ps1 and should not be committed.
- Use least-privilege RBAC for demo operators.
- Keep resource groups short-lived for workshop scenarios.
- For customer environments, integrate this pattern into enterprise landing zone and policy controls.

## Cleanup

```powershell
# From current context:
.\cleanup-demo.ps1 -Force

# Or directly via Azure CLI:
az group delete --name <resource-group-name> --yes --no-wait
```

## Microsoft Learn References

- Azure Monitor Logs best practices (cost):
    - https://learn.microsoft.com/azure/azure-monitor/logs/best-practices-logs#cost-optimization
- Azure Monitor cost optimization:
    - https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost#azure-monitor-logs
- Log Analytics table plans:
    - https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
- Configure Basic Logs:
    - https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
- Auxiliary custom tables:
    - https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary
- DCR transformations and cost:
    - https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations#cost-for-transformations
- Logs Ingestion API:
    - https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview
- Retention configuration:
    - https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure
- Search jobs and restore:
    - https://learn.microsoft.com/azure/azure-monitor/logs/search-jobs
    - https://learn.microsoft.com/azure/azure-monitor/logs/restore
