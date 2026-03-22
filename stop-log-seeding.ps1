$stopFile = Join-Path $PSScriptRoot '.stop-seeding'
New-Item -Path $stopFile -ItemType File -Force | Out-Null
Write-Host 'Stop signal created. Seeding loop will stop shortly.' -ForegroundColor Yellow
