<#
.SYNOPSIS
    Sends sample log data to the deployed Log Analytics workspace via DCR Ingestion API.

.DESCRIPTION
    Generates and sends sample data to both Analytics and Basic tables to demonstrate:
    - DCR transformation filtering (only Warning/Error/Critical reach Analytics table)
    - Basic plan ingestion for debug/verbose data
    - Volume comparison between raw vs. transformed data

.NOTES
    Run deploy.ps1 first, then: . .\.env.ps1; .\send-sample-data.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [int]$EventCount = 200,

    [Parameter(Mandatory = $false)]
    [int]$TraceCount = 500,

    [Parameter(Mandatory = $false)]
    [int]$AuxCount = 300
)

$ErrorActionPreference = "Stop"

$envFilePath = Join-Path $PSScriptRoot '.env.ps1'

# ---- Load environment ----
if (-not $env:DCE_ENDPOINT) {
    if (Test-Path $envFilePath) {
        . $envFilePath
    } else {
        Write-Error "Run deploy.ps1 first, then: . .\.env.ps1"
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($env:WORKSPACE_NAME) -or [string]::IsNullOrWhiteSpace($env:RESOURCE_GROUP)) {
    Write-Error "Missing WORKSPACE_NAME or RESOURCE_GROUP in .env.ps1. Run quick-deploy again, then reload env with: . .\\.env.ps1"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($env:DCE_ENDPOINT) -or
    [string]::IsNullOrWhiteSpace($env:DCR_ANALYTICS_IMMUTABLE_ID) -or
    [string]::IsNullOrWhiteSpace($env:DCR_BASIC_IMMUTABLE_ID) -or
    [string]::IsNullOrWhiteSpace($env:DCR_AUXILIARY_IMMUTABLE_ID)) {
    Write-Error "Missing DCE/DCR values in .env.ps1. Re-run quick-deploy and reload env: . .\\.env.ps1"
    exit 1
}

try {
    $workspaceIdCheck = az monitor log-analytics workspace show -g $env:RESOURCE_GROUP -n $env:WORKSPACE_NAME --query id -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workspaceIdCheck)) {
        throw "Workspace lookup failed"
    }
} catch {
    Write-Error "Workspace from .env.ps1 was not found (stale env). Re-run quick-deploy and then reload env: . .\\.env.ps1"
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Sending Sample Data for Cost Optimization Demo" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ---- Token + resilient ingestion helpers ----
function Get-MonitorHeaders {
    $token = ''
    try {
        $token = az account get-access-token --resource "https://monitor.azure.com/" --query accessToken -o tsv 2>$null
    } catch {
        $token = ''
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        try {
            $token = az account get-access-token --resource "https://monitor.azure.com" --query accessToken -o tsv 2>$null
        } catch {
            $token = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        try {
            $token = az account get-access-token --scope "https://monitor.azure.com//.default" --query accessToken -o tsv 2>$null
        } catch {
            $token = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Could not acquire monitor ingestion token. Fix: az logout ; az login --use-device-code ; az account set --subscription <subscription-id> ; az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv"
    }

    return @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/json"
    }
}

function Wait-DceEndpointReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [int]$MaxAttempts = 12,
        [int]$DelaySeconds = 10
    )

    $hostName = ''
    try {
        $uri = [System.Uri]$Endpoint
        $hostName = $uri.Host
    } catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($hostName)) {
        return
    }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            [System.Net.Dns]::GetHostAddresses($hostName) | Out-Null
            Write-Host "DCE endpoint DNS is ready: $hostName" -ForegroundColor Green
            return $true
        } catch {
            if ($i -eq $MaxAttempts) {
                Write-Host "DCE endpoint DNS is not ready yet: $hostName" -ForegroundColor Yellow
                Write-Host "If this is a fresh deployment, wait 2-5 minutes and retry send-sample-data." -ForegroundColor Yellow
                return $false
            }
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $true
}

function Invoke-IngestionWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 5
    )

    $attempt = 0
    $headers = Get-MonitorHeaders

    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            Invoke-RestMethod -Uri $Url -Method Post -Headers $headers -Body $Body | Out-Null
            return $true
        } catch {
            $statusCode = 0
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($attempt -ge $MaxAttempts) {
                throw
            }

            # 401/403 are often resolved by refreshing token and retrying after short delay.
            if ($statusCode -in @(401, 403)) {
                $headers = Get-MonitorHeaders
            }

            $delay = [math]::Min(10, [math]::Pow(2, $attempt))
            Start-Sleep -Seconds $delay
        }
    }

    return $false
}

Write-Host "Getting access token..." -ForegroundColor Yellow
if (-not (Wait-DceEndpointReady -Endpoint $env:DCE_ENDPOINT)) {
    Write-Error "DCE endpoint is not reachable yet. Stop here to avoid noisy failed batches; retry in 2-5 minutes."
    exit 1
}

try {
    $null = Get-MonitorHeaders
    Write-Host "Monitor ingestion token acquired." -ForegroundColor Green
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$failedBatches = 0

# ============================================================================
# DEMO: Send events to Analytics table (DCR will FILTER these)
# - Sends all severities, but DCR transformation drops Info/Debug
# - Also sends extra columns that DCR will strip
# ============================================================================
Write-Host ""
Write-Host "--- Analytics Table: Sending $EventCount events (all severities) ---" -ForegroundColor Yellow
Write-Host "    DCR will FILTER to only Warning/Error/Critical" -ForegroundColor DarkYellow
Write-Host "    DCR will DROP VerbosePayload, StackTrace, InternalDebugInfo columns" -ForegroundColor DarkYellow

$severities = @("Debug", "Info", "Info", "Info", "Warning", "Error", "Critical")
$eventNames = @("UserLogin", "PageView", "APICall", "DataSync", "CacheRefresh", "DBQuery")
$analyticsUrl = "$($env:DCE_ENDPOINT)/dataCollectionRules/$($env:DCR_ANALYTICS_IMMUTABLE_ID)/streams/Custom-AppEvents_CL?api-version=2023-01-01"

$batchSize = 50
$totalBatches = [math]::Ceiling($EventCount / $batchSize)
$sentCount = 0
$filteredEstimate = 0

for ($batch = 0; $batch -lt $totalBatches; $batch++) {
    $currentBatch = @()
    $batchCount = [math]::Min($batchSize, $EventCount - ($batch * $batchSize))

    for ($i = 0; $i -lt $batchCount; $i++) {
        $severity = $severities | Get-Random
        if ($severity -in @("Warning", "Error", "Critical")) { $filteredEstimate++ }

        $event = @{
            TimeGenerated    = (Get-Date).ToUniversalTime().ToString("o")
            EventName        = $eventNames | Get-Random
            Severity         = $severity
            Message          = "Sample event #$($sentCount + $i + 1) - $severity level event for cost optimization demo"
            UserId           = "user-$(Get-Random -Minimum 1 -Maximum 100)"
            Duration         = [math]::Round((Get-Random -Minimum 10 -Maximum 5000) * 1.0, 2)
            ResourceId       = "/subscriptions/demo/resourceGroups/demo/providers/Microsoft.Web/sites/demo-app"
            VerbosePayload   = "x" * (Get-Random -Minimum 200 -Maximum 1000)   # DCR will DROP
            StackTrace       = "at Method() in file.cs:line $(Get-Random -Minimum 1 -Maximum 500)"  # DCR will DROP
            InternalDebugInfo = "internal-debug-$(Get-Random)"                   # DCR will DROP
        }
        $currentBatch += $event
    }

    $body = $currentBatch | ConvertTo-Json -Depth 5
    try {
        Invoke-IngestionWithRetry -Url $analyticsUrl -Body $body | Out-Null
        $sentCount += $batchCount
        Write-Host "  Batch $($batch+1)/$totalBatches sent ($sentCount/$EventCount events)" -ForegroundColor Green
    } catch {
        $failedBatches++
        Write-Host "  Batch $($batch+1) failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 200
}

$rawSizeKB = [math]::Round($sentCount * 0.8, 1)
$filteredSizeKB = [math]::Round($filteredEstimate * 0.3, 1)
$savings = if ($rawSizeKB -gt 0) { [math]::Round((1 - $filteredSizeKB / $rawSizeKB) * 100, 0) } else { 0 }

Write-Host ""
Write-Host "  ANALYTICS TABLE RESULTS:" -ForegroundColor Cyan
Write-Host "    Raw events sent        : $sentCount" -ForegroundColor White
Write-Host "    Events after DCR filter: ~$filteredEstimate (Warning/Error/Critical only)" -ForegroundColor White
Write-Host "    Est. raw size          : ~${rawSizeKB} KB" -ForegroundColor White
Write-Host "    Est. ingested size     : ~${filteredSizeKB} KB (after filter + column drop)" -ForegroundColor White
Write-Host "    Est. cost savings      : ~${savings}%" -ForegroundColor Green

# ============================================================================
# DEMO: Send traces to Basic table (cheaper ingestion)
# ============================================================================
Write-Host ""
Write-Host "--- Basic Table: Sending $TraceCount debug traces ---" -ForegroundColor Yellow
Write-Host "    Basic plan = ~67% cheaper ingestion vs Analytics" -ForegroundColor DarkYellow

$traceLevels = @("Verbose", "Verbose", "Debug", "Debug", "Info")
$components = @("AuthService", "CacheLayer", "DataPipeline", "APIGateway", "Scheduler")
$basicUrl = "$($env:DCE_ENDPOINT)/dataCollectionRules/$($env:DCR_BASIC_IMMUTABLE_ID)/streams/Custom-DebugTraces_CL?api-version=2023-01-01"

$totalBatches = [math]::Ceiling($TraceCount / $batchSize)
$sentCount = 0

for ($batch = 0; $batch -lt $totalBatches; $batch++) {
    $currentBatch = @()
    $batchCount = [math]::Min($batchSize, $TraceCount - ($batch * $batchSize))

    for ($i = 0; $i -lt $batchCount; $i++) {
        $trace = @{
            TimeGenerated = (Get-Date).ToUniversalTime().ToString("o")
            TraceLevel    = $traceLevels | Get-Random
            Component     = $components | Get-Random
            Message       = "Debug trace #$($sentCount + $i + 1) - $(New-Guid)"
            CorrelationId = [guid]::NewGuid().ToString()
        }
        $currentBatch += $trace
    }

    $body = $currentBatch | ConvertTo-Json -Depth 5
    try {
        Invoke-IngestionWithRetry -Url $basicUrl -Body $body | Out-Null
        $sentCount += $batchCount
        Write-Host "  Batch $($batch+1)/$totalBatches sent ($sentCount/$TraceCount traces)" -ForegroundColor Green
    } catch {
        $failedBatches++
        Write-Host "  Batch $($batch+1) failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 200
}

# ============================================================================
# DEMO: Send signals to Auxiliary table (lowest ingestion cost)
# ============================================================================
if (-not $env:DCR_AUXILIARY_IMMUTABLE_ID) {
    Write-Host "" 
    Write-Host "--- Auxiliary Table: skipped (no DCR_AUXILIARY_IMMUTABLE_ID in .env.ps1) ---" -ForegroundColor Yellow
    Write-Host "    This environment currently doesn't support Auxiliary table plan via ARM." -ForegroundColor DarkYellow
} else {
    Write-Host ""
    Write-Host "--- Auxiliary Table: Sending $AuxCount high-volume signals ---" -ForegroundColor Yellow
    $auxDemoTableName = if ($env:AUX_DEMO_TABLE) { $env:AUX_DEMO_TABLE } else { 'AuxSignals_CL' }
    Write-Host "    Low-touch auxiliary-candidate stream routed to $auxDemoTableName via DCR" -ForegroundColor DarkYellow

    $signalTypes = @("HealthPing", "DiagnosticTick", "ConnectionState", "EdgeMetric")
    $sourceSystems = @("Gateway01", "Gateway02", "AgentPoolA", "AgentPoolB")
    $auxUrl = "$($env:DCE_ENDPOINT)/dataCollectionRules/$($env:DCR_AUXILIARY_IMMUTABLE_ID)/streams/Custom-AuxSignals_CL?api-version=2023-01-01"

    $totalBatches = [math]::Ceiling($AuxCount / $batchSize)
    $sentCount = 0

    for ($batch = 0; $batch -lt $totalBatches; $batch++) {
        $currentBatch = @()
        $batchCount = [math]::Min($batchSize, $AuxCount - ($batch * $batchSize))

        for ($i = 0; $i -lt $batchCount; $i++) {
            $signal = @{
                TimeGenerated    = (Get-Date).ToUniversalTime().ToString("o")
                SignalType       = $signalTypes | Get-Random
                SourceSystem     = $sourceSystems | Get-Random
                PayloadSizeBytes = (Get-Random -Minimum 128 -Maximum 4096)
                Message          = "Aux signal #$($sentCount + $i + 1)"
            }
            $currentBatch += $signal
        }

        $body = $currentBatch | ConvertTo-Json -Depth 5
        try {
            Invoke-IngestionWithRetry -Url $auxUrl -Body $body | Out-Null
            $sentCount += $batchCount
            Write-Host "  Batch $($batch+1)/$totalBatches sent ($sentCount/$AuxCount aux signals)" -ForegroundColor Green
        } catch {
            $failedBatches++
            Write-Host "  Batch $($batch+1) failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 200
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($failedBatches -gt 0) {
    Write-Host " Data generation finished with errors." -ForegroundColor Yellow
    Write-Host " Failed batches: $failedBatches" -ForegroundColor Yellow
    Write-Host " Resolve auth/network issues and retry send-sample-data before running checks." -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Cyan
    exit 1
}

Write-Host " Data generation complete!" -ForegroundColor Green
Write-Host " Wait ~5 minutes for data to appear in Log Analytics" -ForegroundColor Yellow
Write-Host " Then run the KQL queries from queries/ folder to analyze costs" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
