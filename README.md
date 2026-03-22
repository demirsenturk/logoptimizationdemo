# Azure Monitor Logs Cost Optimization Demo

A lightweight demo for Azure Monitor Logs cost optimization and Log Analytics FinOps conversations.

## Prerequisites

- Azure subscription with permissions for resource group deployments and RBAC role assignments
- Azure CLI (`az`) and PowerShell 7 (`pwsh`)
- Logged in via `az login`
- For full demo mode: quota for 2 small VMs in the target region

## Security and Privacy

- Runtime environment values are written to local `.env.ps1` after deployment and are excluded from source control.
- Use `.env.example.ps1` only as a template.

## What Gets Deployed

| Resource | Purpose |
|---|---|
| Log Analytics Workspace | Pricing tier, daily cap, retention settings |
| Custom Table (Analytics plan) | `AppEvents_CL` — full features, standard cost |
| Custom Table (Basic plan) | `DebugTraces_CL` — 68% cheaper ingestion |
| Low-touch Stream Table (Basic fallback) | `AuxSignals_CL` — Auxiliary-candidate long-tail telemetry stream |
| Data Collection Endpoint | Ingestion endpoint for DCR |
| DCR with Transformations | Filters rows + drops columns before ingestion |
| DCR for Basic Table | Routes debug data to cheaper Basic plan |
| Linux VM + AMA + DCR | Real heartbeat/syslog source for non-synthetic proof |
| Windows VM + AMA + DCR | Real heartbeat/event source for non-synthetic proof |
| Key Vault + Storage Diagnostics | Real PaaS diagnostics sent to workspace |
| Storage Account (GRS, Cool) | Data export target with lifecycle policies |
| Data Export Rule | Exports Heartbeat table to blob storage |
| 3 Alert Rules | Daily cap, anomaly detection, noisy table detection |

## Cost Optimization Strategies Demonstrated

1. **Pricing Tier Selection** — Pay-as-you-go vs commitment tiers
2. **Daily Ingestion Cap** — Budget protection against runaway costs
3. **DCR Ingestion-Time Transformations** — Filter rows & drop columns before billing
4. **Table Strategy (Analytics + Basic + Low-touch Stream)** — right data to right economics tier
5. **Retention Tiering** — Interactive (hot) vs Archive (cold) retention
6. **Data Export to Storage** — Blob lifecycle: Cool → Archive → Delete
7. **Proactive Cost Alerts** — Cap warning, anomaly detection, noisy table alerts
8. **Usage Analysis Queries** — KQL queries for ongoing cost review

## Quick Start

### Fast Path (Recommended for 15-Min Demo)

```powershell
# One-command, synthetic-only deployment with a new RG naming convention
.\quick-deploy.ps1 -NamePrefix "logoptdemo"

# Load environment and generate sample data
. .\.env.ps1
.\send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180

# Validate
.\run-demo-checks.ps1 -Timespan P1D
```

## 15-Minute Demo Flow

Use this sequence for a clear, simple walkthrough.

1. Deploy with isolated naming:
    - `.\quick-deploy.ps1 -NamePrefix "logoptdemo"`
2. Seed realistic demo volume:
    - `. .\.env.ps1`
    - `.\send-sample-data.ps1 -EventCount 200 -TraceCount 500 -AuxCount 400`
3. Run health/plan checks:
    - `.\run-demo-checks.ps1 -Timespan P1D`
4. In Log Analytics, run visuals in this order from `queries/demo-visuals.kql`:
    - `VISUAL 1` Cost by table
    - `VISUAL 3` Severity mix after DCR filtering
    - `VISUAL 4` Stream volume (Analytics vs Basic vs Auxiliary/fallback)
    - `VISUAL 6` Monthly run-rate by plan

Suggested story:
- ingest less with DCR
- route data to appropriate table plans
- compare estimated run-rate by plan

## DCR and Tiering Notes

If useful, mention these points during discussion:

1. Ingestion-time optimization with DCR transformations:
    - Show transformation pipeline in [modules/dcr.bicep](modules/dcr.bicep)
    - Explain filter/project behavior for `Custom-AppEvents_CL` and reduced billable ingestion.
2. Table-plan tiering strategy:
    - Show table plan configuration in [modules/tables.bicep](modules/tables.bicep)
    - Demonstrate Analytics (`AppEvents_CL`) vs Basic (`DebugTraces_CL`) vs Auxiliary or fallback (`AuxPortal_CL`/`AuxSignals_CL`).
3. Retention and storage tiering:
    - Show retention and export resources in [modules/workspace.bicep](modules/workspace.bicep) and [modules/storage.bicep](modules/storage.bicep)
    - Explain interactive retention vs archive economics.
4. Operational guardrails:
    - Show scheduled query alerts in [modules/alerts.bicep](modules/alerts.bicep)
    - Demonstrate cap/anomaly/noisy-table controls.
5. Quantified outcome:
    - Run visuals from [queries/demo-visuals.kql](queries/demo-visuals.kql)
    - Run deep analysis from [queries/cost-analysis.kql](queries/cost-analysis.kql)

### Full Path (Real VM/PaaS Sources)

```powershell
# Deploy everything
.\deploy.ps1 -ResourceGroupName "rg-lawopt-demo" -Location "germanywestcentral"

# Load environment variables
. .\.env.ps1

# Send sample data
.\send-sample-data.ps1

# Verify data and cost checks (handles Basic table API correctly)
.\run-demo-checks.ps1

# Optional: if you only want synthetic demo assets
# .\deploy.ps1 -DeployRealVmSource $false -DeployRealWindowsVmSource $false -DeployRealPaaSSources $false

# Run visual deck queries during presentation
# Open queries/demo-visuals.kql in Log Analytics

# Open the Azure Portal and follow DEMO-SCRIPT.md
```

## Deployment Profiles

- Full realistic profile:
    - `-DeployRealVmSource $true -DeployRealWindowsVmSource $true -DeployRealPaaSSources $true`
    - Includes Linux/Windows VM telemetry and Key Vault/Storage diagnostics.
- Lightweight synthetic profile:
    - `-DeployRealVmSource $false -DeployRealWindowsVmSource $false -DeployRealPaaSSources $false`
    - Fastest setup for dry runs.

## Cloud Shell Testing

After publishing to GitHub, use the Cloud Shell runbook in [docs/CLOUD-SHELL-TEST.md](docs/CLOUD-SHELL-TEST.md).

## Optional Microsoft Learn References

Useful references if participants ask for source guidance:

- Azure Monitor Logs best practices (cost optimization):
    - https://learn.microsoft.com/azure/azure-monitor/logs/best-practices-logs#cost-optimization
- Azure Monitor cost optimization guidance:
    - https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost#azure-monitor-logs
- Log Analytics table plans (Analytics, Basic, Auxiliary):
    - https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
- Configure Basic Logs table plan:
    - https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
- Auxiliary custom table setup:
    - https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary
- Data collection transformations (DCR) and cost behavior:
    - https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations#cost-for-transformations
- Logs ingestion API overview:
    - https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview
- Retention and archive settings:
    - https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure
- Search jobs and restored data:
    - https://learn.microsoft.com/azure/azure-monitor/logs/search-jobs
    - https://learn.microsoft.com/azure/azure-monitor/logs/restore

## Project Structure

```
lawopt/
├── main.bicep                  # Main deployment template
├── main.bicepparam             # Parameter file
├── deploy.ps1                  # Deployment script
├── quick-deploy.ps1            # Simplified one-command synthetic deploy
├── send-sample-data.ps1        # Sample data generator
├── run-demo-checks.ps1         # Verification checks (synthetic + Linux/Windows/PaaS)
├── DEMO-SCRIPT.md              # 10-minute demo walkthrough
├── README.md                   # This file
├── modules/
│   ├── workspace.bicep         # LAW with pricing, cap, retention
│   ├── tables.bicep            # Analytics vs Basic plan tables
│   ├── dcr.bicep               # DCE + DCR with transformations
│   ├── storage.bicep           # Storage + lifecycle + data export
│   ├── alerts.bicep            # Cost monitoring alerts
│   ├── real-vm-demo.bicep      # Linux VM + AMA + DCR association
│   ├── real-windows-vm-demo.bicep # Windows VM + AMA + DCR association
│   └── real-paas-demo.bicep    # Key Vault + Storage diagnostics
└── queries/
    ├── cost-analysis.kql       # 7 KQL queries for cost analysis
    ├── demo-visuals.kql        # chart-first visual queries for showcase
    └── verify-and-cleanup.kql  # Verification queries
```

## Auxiliary Plan Note

If `Auxiliary` is enabled in your workspace, you can use a true Auxiliary table (for example `AuxPortal_CL`) and the visual deck will include it automatically. If ARM deployment blocks Auxiliary in a given environment, the demo falls back to `AuxSignals_CL` on Basic and still demonstrates the same low-touch data-stream architecture.

The deployment script now auto-detects existing Auxiliary tables in the target workspace and reuses one for DCR low-touch routing, so sample signals can land in your real Auxiliary table without changing code.

### Use True Auxiliary Tier in a Fresh Environment

Note:
`-AuxTableOverrideName` works only when that table already exists in the target workspace. In a brand-new resource group, there is no workspace yet, so the override is intentionally ignored on first run.

Recommended two-phase flow:

1. Phase 1: Create the workspace and baseline demo resources.
    - `./quick-deploy.ps1 -NamePrefix "logoptdemo"`
2. Phase 2: Create an Auxiliary table in that workspace.
    - In Azure Portal: Log Analytics workspace -> Tables -> Create -> Custom log (DCR-based) -> Plan: Auxiliary.
    - Example table name: `AuxPortal_CL`.
3. Phase 3: Rerun deploy and force routing to that table.
    - `./deploy.ps1 -ResourceGroupName "<same-rg-name>" -Location "germanywestcentral" -AuxTableOverrideName "AuxPortal_CL" -DeployRealVmSource $false -DeployRealWindowsVmSource $false -DeployRealPaaSSources $false`
4. Verify table plan and ingestion path.
    - `az monitor log-analytics workspace table show -g "<same-rg-name>" --workspace-name "<workspace-name>" -n AuxPortal_CL --query "{name:name,plan:plan}" -o table`

## Cleanup

```powershell
az group delete --name <your-resource-group> --yes --no-wait
# or, from the generated .env.ps1 context:
.\cleanup-demo.ps1 -Force
```
