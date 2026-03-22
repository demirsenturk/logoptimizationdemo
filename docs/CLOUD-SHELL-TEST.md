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

## 3) Deploy Demo

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

## 6) Optional Smoke Queries

```powershell
az monitor log-analytics query --workspace $env:WORKSPACE_ID --analytics-query "Usage | where TimeGenerated > ago(1d) | where IsBillable == true | summarize IngestedMB=round(sum(Quantity),2) by DataType | order by IngestedMB desc | take 10" -o table
```

## 7) Cleanup

```powershell
az group delete --name "rg-lawopt-demo-cs" --yes --no-wait
```

## Troubleshooting

- If `az` prompts to install an extension, allow it and rerun the command.
- If Auxiliary creation fallback appears, this only affects ARM-created AuxSignals table plan. Existing Auxiliary tables are still reused automatically.
- If VM/PaaS telemetry is zero right after deployment, wait and rerun checks after 10 minutes.
