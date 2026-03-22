# Azure Monitor Logs FinOps Showcase Environment

This repository is a practical, customer-shareable showcase for Microsoft FinOps patterns on Azure Monitor Logs.

It demonstrates how to reduce logging costs while keeping operational visibility by combining:

- Data Collection Rules (DCR) transformation and filtering at ingestion time
- Table plan tiering (Analytics, Basic, and Auxiliary-ready routing)
- Retention and export strategy for long-term economics
- Commitment tier and daily cap governance decisions
- Alert-driven guardrails and KQL verification

Use this repo for a live session, a post-session customer handoff, or a self-paced lab.

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
