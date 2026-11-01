param(
    [string]$BaseUrl = 'http://localhost:8081'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$override = Join-Path ([IO.Path]::GetTempPath()) ("lab3-degraded-$([guid]::NewGuid().ToString('N')).yml")

# Break only api_b's database connection. The other nodes keep the real DB.
Set-Content -LiteralPath $override -Encoding utf8 -Value @'
services:
  api_b:
    environment:
      ConnectionStrings__DefaultConnection: "Host=unreachable.invalid;Port=5432;Database=online_testing;Username=app;Password=invalid;Timeout=1"
'@

Push-Location $projectRoot
try {
    docker compose -f docker-compose.yml -f $override up -d --no-build --force-recreate api_b | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not start degraded api_b.' }
    Start-Sleep -Seconds 3

    foreach ($path in @('/health', '/api/tests')) {
        $responses = @(1..40 | ForEach-Object {
            $response = Invoke-WebRequest -Uri "$BaseUrl$path" -TimeoutSec 10 -SkipHttpErrorCheck
            [pscustomobject]@{
                Status = [int]$response.StatusCode
                Instance = [string]$response.Headers['X-Instance-ID']
            }
        })
        $bad = @($responses | Where-Object { $_.Status -ne 200 -or $_.Instance -notin @('api-a', 'api-c') })
        if ($bad.Count -gt 0) { throw "$path had $($bad.Count) unsuccessful or degraded-node responses." }
        Write-Host "$path`: 40/40 HTTP 200 from api-a or api-c."
    }
    Write-Host 'PASS: Nginx passively excludes a node with failed DB readiness or HTTP 500.'
}
finally {
    try {
        docker compose up -d --no-build --force-recreate api_b | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not restore api_b.' }
    }
    finally {
        Remove-Item -LiteralPath $override -ErrorAction SilentlyContinue
        Pop-Location
    }
}
