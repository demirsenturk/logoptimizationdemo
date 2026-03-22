# Azure Monitor Logs Cost Optimization - Showcase Script (10 Minutes)

## Goal
Show a practical, deployable cost optimization architecture with live data:
1. Ingestion optimization (DCR transformation)
2. Data-tiering strategy (Analytics, Basic, Auxiliary or fallback)
3. Retention and export tiering
4. Proactive guardrails (alerts and checks)
5. Real source validation (Linux VM, Windows VM, Key Vault, Storage)

## Pre-Demo Checklist (Run 15-30 min before session)

```powershell
# Ensure deployment and permissions are current
.\deploy.ps1 -ResourceGroupName "rg-lawopt-demo" -Location "germanywestcentral" -UseAuxiliaryPlan $true

# Load environment and seed data
. .\.env.ps1
.\send-sample-data.ps1 -EventCount 200 -TraceCount 500 -AuxCount 400

# Validate tables and plan modes
.\run-demo-checks.ps1
```

If you want richer charts at demo time, run one extra seed cycle 5 minutes before presenting.
Real VM/PaaS telemetry can take 5-15 minutes after first deployment.
If an Auxiliary table already exists in the workspace (for example `AuxPortal_CL`), deployment reuses it automatically for low-touch DCR routing.

## Optional Best-Practice Callouts

Use these short callouts if you want to connect the live demo to Microsoft guidance without making the session too formal.

1. DCR ingestion optimization:
	- "We filter and project at ingestion time so we only pay for data we need."
2. Table tiering strategy:
	- "We keep high-value logs in Analytics and route low-touch streams to Basic/Auxiliary-style paths."
3. Retention tiering:
	- "We combine interactive retention for short-term operations with cheaper long-term storage strategy."

## 10-Minute Talk Track

### 0:00-1:00 - Opening
Say:
"I will show how we reduce log costs without losing operational visibility. The model is simple: ingest less, store smart, and monitor continuously."

Show:
1. Resource group with deployed assets
2. Log Analytics workspace overview

### 1:00-3:00 - Cost Drivers and Baseline
Say:
"In Azure Monitor Logs, the biggest cost drivers are ingestion volume, table plan, and retention."

Show:
1. Workspace Usage and estimated costs
2. Query: Visual 1 from queries/demo-visuals.kql (Cost by table)

Point:
"You can immediately see which table families dominate spend."

### 3:00-5:00 - Ingestion-Time Optimization (Highest ROI)
Say:
"The fastest savings is to optimize before billing happens."

Show:
1. DCR for AppEvents stream
2. Transformation KQL filter/project logic
3. Query: Visual 3 from queries/demo-visuals.kql (Severity mix)

Point:
"We drop low-value events and verbose columns at ingestion time."

### 5:00-7:00 - Table Plan Strategy (Tiered Data)
Say:
"We split logs by usage profile:"
1. AppEvents_CL -> Analytics (high-value ops)
2. DebugTraces_CL -> Basic (troubleshooting)
3. Aux stream table -> Auxiliary if enabled, otherwise Basic fallback

Show:
1. Workspace table list and plan column
2. Query: Visual 4 from queries/demo-visuals.kql (volume by stream)
3. Query: Visual 6 from queries/demo-visuals.kql (monthly run-rate by plan)

If asked about Auxiliary:
"This workspace supports true Auxiliary when enabled. If any environment blocks it, the deployment auto-falls back so the architecture is still demonstrable."

### 7:00-8:00 - Real Telemetry (Not Synthetic)
Say:
"This demo is not only seeded data. We also ingest from real Azure resources via AMA and diagnostics."

Show:
1. `run-demo-checks.ps1` output for Linux VM (Heartbeat, Syslog)
2. `run-demo-checks.ps1` output for Windows VM (Heartbeat, Event)
3. `run-demo-checks.ps1` output for Key Vault/Storage diagnostics

Point:
"Synthetic streams make the timing deterministic, while real resources prove this architecture works in production patterns."

### 8:00-9:00 - Retention + Export Tiering
Say:
"Hot, warm, and cold data each get their own economics."

Show:
1. Table retention settings
2. Storage lifecycle policy (Cool -> Archive -> Delete)
3. Data export rule

Point:
"Retention and export are where long-horizon cost control happens."

### 9:00-9:40 - Guardrails and Operational Safety
Say:
"Optimization only works if you keep it stable over time."

Show:
1. Alert rules (cap threshold, anomaly, noisy table)
2. Query: Visual 5 from queries/demo-visuals.kql (daily cap usage KPI)

### 9:40-10:00 - Wrap-Up
Say:
"This design is reusable:"
1. DCR transformation for ingestion control
2. Right table plan per data behavior
3. Retention/export tiering
4. Alert-driven governance

Close:
"We turned log cost optimization into policy + automation, not ad-hoc cleanup."

## Visual Run Order (Quick Reference)

Run these from queries/demo-visuals.kql in this order:
1. Visual 1 - Cost by table
2. Visual 3 - Severity mix
3. Visual 4 - Stream volume
4. Visual 6 - Monthly run-rate
5. Visual 5 - Daily cap KPI

## Backup Queries (If Chart UI misbehaves)

Use queries/cost-analysis.kql:
1. Query 1 (billable by table)
2. Query 4 (plan comparison)
3. Query 6 (daily cap)
4. Query 7 (commitment tier recommendation)

## Post-Demo

```powershell
# Optional cleanup
az group delete --name rg-lawopt-demo --yes --no-wait
```
