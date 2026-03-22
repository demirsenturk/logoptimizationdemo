# Azure Monitor Logs Cost Optimization Demo

Deployable demo showcasing **8 cost optimization strategies** for Azure Monitor Logs, following [Microsoft best practices](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/best-practices-logs#cost-optimization).

## Prerequisites

- Azure subscription with permissions for resource group deployments and RBAC role assignments
- Azure CLI (`az`) and PowerShell 7 (`pwsh`)
- Logged in via `az login`
- For full demo mode: quota for 2 small VMs in the target region

## Security and Privacy

- This repository is designed to avoid committed secrets.
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

## Project Structure

```
lawopt/
├── main.bicep                  # Main deployment template
├── main.bicepparam             # Parameter file
├── deploy.ps1                  # Deployment script
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

## Cleanup

```powershell
az group delete --name rg-lawopt-demo --yes --no-wait
```
