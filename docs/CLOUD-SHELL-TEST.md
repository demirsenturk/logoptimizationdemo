# Cloud Shell Test Runbook

Use this after publishing the repo to GitHub.

## 1) Open Cloud Shell

1. Go to https://shell.azure.com.
2. Choose Bash or PowerShell. This runbook uses PowerShell commands.
3. Verify subscription:

```powershell
az account show --query "{name:name,id:id}" -o table
```

If needed:

```powershell
az account set --subscription "<subscription-id-or-name>"
```

## 2) Clone Repository

```powershell
git clone https://github.com/demirsenturk/logoptimizationdemo.git
cd logoptimizationdemo
```

If you are testing from a fork, replace the clone URL with your fork path.

## 3) Deploy Demo

Simple profile (recommended first):

```powershell
pwsh ./quick-deploy.ps1 -NamePrefix "logoptdemo" -Location "germanywestcentral"
```

This creates an isolated resource group name like `rg-logoptdemo-xxxx`.

If you want to force using a known Auxiliary table name:

```powershell
pwsh ./quick-deploy.ps1 -NamePrefix "logoptdemo" -Location "germanywestcentral" -AuxTableOverrideName "AuxPortal_CL"
```

Note:
In a brand-new resource group, `AuxTableOverrideName` is ignored on first deployment if the table does not exist yet.

To use true Auxiliary tier in a fresh environment:

1. Run `quick-deploy.ps1` once to create the workspace.
2. Create an Auxiliary table in that workspace from Azure Portal (DCR-based custom table, plan = Auxiliary).
3. Run deploy again on the same resource group with `-AuxTableOverrideName "<your-aux-table>"`.

Full demo (includes Linux VM, Windows VM, and PaaS telemetry sources):

```powershell
pwsh ./deploy.ps1 -ResourceGroupName "rg-lawopt-demo-cs" -Location "germanywestcentral" -UseAuxiliaryPlan $true -DeployRealVmSource $true -DeployRealWindowsVmSource $true -DeployRealPaaSSources $true
```

Lightweight demo (synthetic only, faster and cheaper):

```powershell
pwsh ./deploy.ps1 -ResourceGroupName "rg-lawopt-demo-cs" -Location "germanywestcentral" -UseAuxiliaryPlan $true -DeployRealVmSource $false -DeployRealWindowsVmSource $false -DeployRealPaaSSources $false
```

## 4) Load Environment and Seed Data

```powershell
. ./.env.ps1
pwsh ./send-sample-data.ps1 -EventCount 200 -TraceCount 500 -AuxCount 400
```

## 5) Validate End-to-End

```powershell
pwsh ./run-demo-checks.ps1 -Timespan P1D
```

Expected:
- AppEvents and DebugTraces have counts.
- Low-touch stream check resolves to Auxiliary table when present (for example AuxPortal_CL), otherwise AuxSignals_CL.
- Linux/Windows/PaaS checks may need 5-15 minutes after first deploy.

Quick copy/paste flow:

```powershell
git pull origin main
pwsh ./quick-deploy.ps1 -NamePrefix "logoptdemo" -Location "germanywestcentral"
. ./.env.ps1
pwsh ./send-sample-data.ps1 -EventCount 120 -TraceCount 240 -AuxCount 180
pwsh ./run-demo-checks.ps1 -Timespan P1D
```

## 6) Optional Smoke Queries

```powershell
az monitor log-analytics query --workspace $env:WORKSPACE_ID --analytics-query "Usage | where TimeGenerated > ago(1d) | where IsBillable == true | summarize IngestedMB=round(sum(Quantity),2) by DataType | order by IngestedMB desc | take 10" -o table
```

## 7) Cleanup

```powershell
az group delete --name "rg-lawopt-demo-cs" --yes --no-wait
```

## Troubleshooting (Common)

- If `az` prompts to install an extension, allow it and rerun the command.
- If Auxiliary creation fallback appears, this only affects ARM-created AuxSignals table plan. Existing Auxiliary tables are still reused automatically.
- If VM/PaaS telemetry is zero right after deployment, wait and rerun checks after 10 minutes.

## Microsoft Learn References

- Azure Monitor Logs best practices (cost):
	- https://learn.microsoft.com/azure/azure-monitor/logs/best-practices-logs#cost-optimization
- Table plans (Analytics, Basic, Auxiliary):
	- https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs#table-plans
- Basic Logs configuration:
	- https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure
- Auxiliary custom table setup:
	- https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table-auxiliary
- DCR transformations and cost:
	- https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations#cost-for-transformations

## Pre-Publish Safety Check

Run these locally before pushing:

```powershell
git status -sb
git ls-files
```

Confirm all of the following:
- `.env.ps1` is not tracked.
- No access tokens or passwords are hardcoded.
- No personal or tenant-specific values are embedded in docs/scripts.
