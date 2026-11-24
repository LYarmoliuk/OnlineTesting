$ErrorActionPreference = 'Stop'
function Assert-Ok($Condition, $Message) { if (-not $Condition) { throw $Message } }
$root = (Get-Location).Path
while ($root -and -not (Test-Path (Join-Path $root 'docker-compose.yml'))) {
    $parent = Split-Path $root -Parent
    if ($parent -eq $root) { $root = $null } else { $root = $parent }
}
Assert-Ok $root 'Run from inside the OnlineTesting project folder.'
$required = @(
    'docker-compose.profiling.yml', 'profiling\lab9.js',
    'scripts\run-lab9.ps1', 'docs\profiling\report-template.md',
    'backend\OnlineTesting.Api\Profiling\Lab9Diagnostics.cs'
)
foreach ($file in $required) { Assert-Ok (Test-Path (Join-Path $root $file)) "Missing Lab 9 file: $file" }
Assert-Ok (Get-Command docker -ErrorAction SilentlyContinue) 'Docker CLI is unavailable.'
$compose = @('-f', 'docker-compose.yml', '-f', 'docker-compose.profiling.yml')
& docker compose @compose config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration is invalid.' }
$running = (& docker compose @compose ps --status running --services) -join "`n"
foreach ($service in @('api_a','api_b','api_c','db','redis','jaeger')) {
    Assert-Ok ($running -match "(?m)^$service$") "Required service is not running: $service"
}
$health = Invoke-RestMethod 'http://localhost:8081/health' -TimeoutSec 10
Assert-Ok ($health.status -eq 'healthy') 'API health endpoint reports unhealthy.'
$jaeger = Invoke-WebRequest 'http://localhost:16686/' -TimeoutSec 10
Assert-Ok ($jaeger.StatusCode -eq 200) 'Jaeger UI is not reachable.'
Write-Host 'PASS Lab 9: files, compose, API/DB/Redis replicas, and Jaeger are ready.' -ForegroundColor Green
