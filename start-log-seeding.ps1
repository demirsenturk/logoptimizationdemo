param(
    [Parameter(Mandatory = $false)]
    [int]$IntervalMinutes = 30,

    [Parameter(Mandatory = $false)]
    [int]$EventCount = 20,

    [Parameter(Mandatory = $false)]
    [int]$TraceCount = 60
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$stopFile = Join-Path $root '.stop-seeding'
$logDir = Join-Path $root 'seeding-logs'
$runLog = Join-Path $logDir 'seed-run.log'

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

if (Test-Path $stopFile) {
    Remove-Item $stopFile -Force
}

if (Test-Path (Join-Path $root '.env.ps1')) {
    . (Join-Path $root '.env.ps1')
} else {
    throw 'Missing .env.ps1. Run deploy.ps1 first.'
}

"[$(Get-Date -Format o)] Starting log seeding. Interval=$IntervalMinutes min, EventCount=$EventCount, TraceCount=$TraceCount" | Out-File -FilePath $runLog -Append -Encoding utf8
Write-Host 'Log seeding started. Create .stop-seeding file or run stop-log-seeding.ps1 to stop.' -ForegroundColor Green

while (-not (Test-Path $stopFile)) {
    try {
        $stamp = Get-Date -Format o
        "[$stamp] Seeding batch started" | Out-File -FilePath $runLog -Append -Encoding utf8

        # Add slight jitter to make data look more organic.
        $events = [Math]::Max(5, $EventCount + (Get-Random -Minimum -5 -Maximum 6))
        $traces = [Math]::Max(10, $TraceCount + (Get-Random -Minimum -10 -Maximum 11))

        & (Join-Path $root 'send-sample-data.ps1') -EventCount $events -TraceCount $traces -AuxCount 0 2>&1 |
            Out-File -FilePath $runLog -Append -Encoding utf8

        "[$(Get-Date -Format o)] Seeding batch completed (EventCount=$events, TraceCount=$traces)" | Out-File -FilePath $runLog -Append -Encoding utf8
    }
    catch {
        "[$(Get-Date -Format o)] ERROR: $($_.Exception.Message)" | Out-File -FilePath $runLog -Append -Encoding utf8
    }

    for ($i = 0; $i -lt ($IntervalMinutes * 6); $i++) {
        if (Test-Path $stopFile) { break }
        Start-Sleep -Seconds 10
    }
}

"[$(Get-Date -Format o)] Seeding stopped" | Out-File -FilePath $runLog -Append -Encoding utf8
Write-Host 'Log seeding stopped.' -ForegroundColor Yellow
