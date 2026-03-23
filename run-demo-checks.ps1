param(
    [Parameter(Mandatory = $false)]
    [string]$Timespan = 'PT1H'
)

$ErrorActionPreference = 'Stop'

$envFilePath = Join-Path $PSScriptRoot '.env.ps1'

if (-not $env:WORKSPACE_ID) {
    if (Test-Path $envFilePath) {
        . $envFilePath
    } else {
        throw "Missing WORKSPACE_ID. Run deploy script first."
    }
}

if ([string]::IsNullOrWhiteSpace($env:WORKSPACE_NAME) -or [string]::IsNullOrWhiteSpace($env:RESOURCE_GROUP)) {
    throw "Missing WORKSPACE_NAME or RESOURCE_GROUP in .env.ps1. Run quick-deploy again, then reload env with: . .\\.env.ps1"
}

try {
    $workspaceIdCheck = az monitor log-analytics workspace show -g $env:RESOURCE_GROUP -n $env:WORKSPACE_NAME --query id -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workspaceIdCheck)) {
        throw "Workspace lookup failed"
    }
} catch {
    throw "Workspace from .env.ps1 was not found (stale env). Re-run quick-deploy and reload env: . .\\.env.ps1"
}

Write-Host '=== Demo Verification Checks ===' -ForegroundColor Cyan
Write-Host "Workspace: $($env:WORKSPACE_NAME) ($($env:WORKSPACE_ID))" -ForegroundColor Gray

function Get-LogAnalyticsToken {
    az account get-access-token --resource "https://api.loganalytics.io" --query accessToken -o tsv
}

function Test-WorkspaceTableExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    try {
        az monitor log-analytics workspace table show -g $env:RESOURCE_GROUP --workspace-name $env:WORKSPACE_NAME -n $TableName --query name -o tsv 2>$null | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [int]$MaxAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $Action
        } catch {
            if ($attempt -eq $MaxAttempts) { throw }
            Start-Sleep -Seconds ([Math]::Min(10, [Math]::Pow(2, $attempt)))
        }
    }
}

function Get-BasicLikeTableCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$TimeWindow
    )

    if (-not (Test-WorkspaceTableExists -TableName $TableName)) {
        return 0
    }

    $token = Get-LogAnalyticsToken
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
    $uri = "https://api.loganalytics.io/v1/workspaces/$($env:WORKSPACE_ID)/search"
    $body = @{ query = "$TableName | summarize C=count()"; timespan = $TimeWindow } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
    $rows = $resp.tables.rows
    if ($rows.Count -gt 0) {
        return [int]$rows[0][0]
    }
    return 0
}

function Get-AnalyticsCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    try {
        $count = az monitor log-analytics query --workspace $env:WORKSPACE_ID --analytics-query $Query --query "tables[0].rows[0][0]" -o tsv
        if ([string]::IsNullOrWhiteSpace($count)) {
            return 0
        }
        return [int]$count
    } catch {
        return 0
    }
}

# Analytics query endpoint works for Analytics tables and Usage.
Write-Host ''
Write-Host '[1/4] Analytics table check (AppEvents_CL)' -ForegroundColor Yellow
Invoke-WithRetry {
    az monitor log-analytics query --workspace $env:WORKSPACE_ID --analytics-query "AppEvents_CL | where TimeGenerated > ago(60m) | summarize AppEventsCount=count()" -o table
} | Out-Host

Write-Host ''
Write-Host '[2/4] Billable usage by table (Usage)' -ForegroundColor Yellow
Invoke-WithRetry {
    az monitor log-analytics query --workspace $env:WORKSPACE_ID --analytics-query "Usage | where TimeGenerated > ago(1d) | where IsBillable == true | summarize IngestedMB=round(sum(Quantity),2) by DataType | sort by IngestedMB desc | take 10" -o table
} | Out-Host

# Basic/Auxiliary tables require /search API, not /query.
Write-Host ''
Write-Host '[3/4] Basic/Auxiliary-compatible check via /search API (DebugTraces_CL)' -ForegroundColor Yellow
Invoke-WithRetry {
    $token = Get-LogAnalyticsToken
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
    $uri = "https://api.loganalytics.io/v1/workspaces/$($env:WORKSPACE_ID)/search"
    $body = @{ query = "DebugTraces_CL | summarize DebugTracesCount=count()"; timespan = $Timespan } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
    $rows = $resp.tables.rows
    if ($rows.Count -gt 0) {
        Write-Host ("DebugTracesCount: {0}" -f $rows[0][0]) -ForegroundColor Green
    } else {
        Write-Host 'DebugTracesCount: 0' -ForegroundColor Yellow
    }
}

Write-Host ''
$auxPortalCount = 0
$auxSignalsCount = 0
$auxPortalExists = Test-WorkspaceTableExists -TableName 'AuxPortal_CL'
$auxSignalsExists = Test-WorkspaceTableExists -TableName 'AuxSignals_CL'
if ($auxPortalExists) {
    try { $auxPortalCount = Get-BasicLikeTableCount -TableName 'AuxPortal_CL' -TimeWindow $Timespan } catch {}
}
if ($auxSignalsExists) {
    try { $auxSignalsCount = Get-BasicLikeTableCount -TableName 'AuxSignals_CL' -TimeWindow $Timespan } catch {}
}

$preferredAuxTable = if ($env:AUX_DEMO_TABLE) { $env:AUX_DEMO_TABLE } else { '' }
$auxTableName = ''
if (-not [string]::IsNullOrWhiteSpace($preferredAuxTable) -and (Test-WorkspaceTableExists -TableName $preferredAuxTable)) {
    $auxTableName = $preferredAuxTable
} elseif ($auxPortalCount -ge $auxSignalsCount -and $auxPortalExists) {
    $auxTableName = 'AuxPortal_CL'
} elseif ($auxSignalsExists) {
    $auxTableName = 'AuxSignals_CL'
} else {
    $auxTableName = 'AuxSignals_CL'
}
Write-Host "[4/4] Low-touch stream check via /search API ($auxTableName)" -ForegroundColor Yellow
Invoke-WithRetry {
    $token = Get-LogAnalyticsToken
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
    $uri = "https://api.loganalytics.io/v1/workspaces/$($env:WORKSPACE_ID)/search"
    $body = @{ query = "$auxTableName | summarize AuxSignalsCount=count()"; timespan = $Timespan } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
    $rows = $resp.tables.rows
    if ($rows.Count -gt 0) {
        Write-Host ("AuxSignalsCount: {0}" -f $rows[0][0]) -ForegroundColor Green
    } else {
        Write-Host 'AuxSignalsCount: 0' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'AuxSignals plan in workspace:' -ForegroundColor Cyan
$tablePlan = ''
try {
    $tablePlan = az monitor log-analytics workspace table show -g $env:RESOURCE_GROUP --workspace-name $env:WORKSPACE_NAME -n $auxTableName --query plan -o tsv
    Write-Host ("{0} plan: {1}" -f $auxTableName, $tablePlan) -ForegroundColor Green
} catch {
    Write-Host 'Could not read auxiliary stream table plan.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Auxiliary note:' -ForegroundColor Cyan
if ($tablePlan -eq 'Auxiliary') {
    Write-Host ("Auxiliary plan is enabled and active for {0}." -f $auxTableName) -ForegroundColor Green
} else {
    Write-Host ("Auxiliary plan is not active here; {0} is running as Basic fallback." -f $auxTableName) -ForegroundColor Yellow
}

if ($auxPortalExists -and $auxSignalsExists) {
    Write-Host ("Aux table counts in {0}: AuxPortal_CL={1}, AuxSignals_CL={2}" -f $Timespan, $auxPortalCount, $auxSignalsCount) -ForegroundColor Gray
}

Write-Host ''
Write-Host '=== Real Source Checks (Linux / Windows / PaaS) ===' -ForegroundColor Cyan

$hasLinuxTarget = -not [string]::IsNullOrWhiteSpace($env:REAL_VM_NAME)
$hasWindowsTarget = -not [string]::IsNullOrWhiteSpace($env:REAL_WINDOWS_VM_NAME)
$hasPaaSTarget = (-not [string]::IsNullOrWhiteSpace($env:REAL_KEYVAULT_NAME)) -or (-not [string]::IsNullOrWhiteSpace($env:REAL_STORAGE_NAME))

if (-not ($hasLinuxTarget -or $hasWindowsTarget -or $hasPaaSTarget)) {
    Write-Host 'Real-source checks skipped: this looks like a synthetic-only deployment profile.' -ForegroundColor Yellow
    Write-Host 'To enable VM/PaaS checks, deploy with real sources and reload .env.ps1 from that deployment.' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Readout guidance:' -ForegroundColor Cyan
    Write-Host '- VM heartbeat/event/syslog can take 5-15 minutes after first deployment.' -ForegroundColor Gray
    Write-Host '- Key Vault and Storage diagnostics appear after activity hits those resources.' -ForegroundColor Gray
    return
}

$linuxVmFilter = if ($env:REAL_VM_NAME) {
    "Computer has '$($env:REAL_VM_NAME)'"
} else {
    "Computer startswith 'vm-lawopt'"
}

$linuxHeartbeat = Get-AnalyticsCount -Query "Heartbeat | where TimeGenerated > ago(60m) | where $linuxVmFilter | summarize C=count()"
$linuxSyslog = Get-AnalyticsCount -Query "Syslog | where TimeGenerated > ago(60m) | where $linuxVmFilter | summarize C=count()"

if ($env:REAL_VM_NAME) {
    Write-Host ("Linux VM ({0}): Heartbeat={1}, Syslog={2}" -f $env:REAL_VM_NAME, $linuxHeartbeat, $linuxSyslog) -ForegroundColor White
} else {
    Write-Host ("Linux VM: Heartbeat={0}, Syslog={1}" -f $linuxHeartbeat, $linuxSyslog) -ForegroundColor White
}

$windowsVmFilter = if ($env:REAL_WINDOWS_VM_NAME) {
    "Computer has '$($env:REAL_WINDOWS_VM_NAME)'"
} else {
    "Computer startswith 'vmwin-lawopt'"
}

$windowsHeartbeat = Get-AnalyticsCount -Query "Heartbeat | where TimeGenerated > ago(60m) | where $windowsVmFilter | summarize C=count()"
$windowsEvents = Get-AnalyticsCount -Query "Event | where TimeGenerated > ago(60m) | where $windowsVmFilter | summarize C=count()"

if ($env:REAL_WINDOWS_VM_NAME) {
    Write-Host ("Windows VM ({0}): Heartbeat={1}, Event={2}" -f $env:REAL_WINDOWS_VM_NAME, $windowsHeartbeat, $windowsEvents) -ForegroundColor White
} else {
    Write-Host ("Windows VM: Heartbeat={0}, Event={1}" -f $windowsHeartbeat, $windowsEvents) -ForegroundColor White
}

$paasDiag = Get-AnalyticsCount -Query "AzureDiagnostics | where TimeGenerated > ago(60m) | where ResourceProvider in ('MICROSOFT.KEYVAULT','MICROSOFT.STORAGE') | summarize C=count()"
if ($env:REAL_KEYVAULT_NAME -or $env:REAL_STORAGE_NAME) {
    Write-Host ("PaaS diagnostics (KV/Storage): AzureDiagnostics={0} (KV={1}, Storage={2})" -f $paasDiag, $env:REAL_KEYVAULT_NAME, $env:REAL_STORAGE_NAME) -ForegroundColor White
} else {
    Write-Host ("PaaS diagnostics (KV/Storage): AzureDiagnostics={0}" -f $paasDiag) -ForegroundColor White
}

Write-Host ''
Write-Host 'Readout guidance:' -ForegroundColor Cyan
Write-Host '- VM heartbeat/event/syslog can take 5-15 minutes after first deployment.' -ForegroundColor Gray
Write-Host '- Key Vault and Storage diagnostics appear after activity hits those resources.' -ForegroundColor Gray
