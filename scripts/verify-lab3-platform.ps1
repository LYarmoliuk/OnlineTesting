param(
    [string]$BaseUrl = 'http://localhost:8081'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Request($path) {
    $response = Invoke-WebRequest -Uri "$BaseUrl$path" -TimeoutSec 10 -SkipHttpErrorCheck
    if ($response.StatusCode -ne 200) {
        throw "$path returned $($response.StatusCode), expected 200."
    }
    $instance = [string]$response.Headers['X-Instance-ID']
    if ($instance -notin @('api-a', 'api-b', 'api-c')) {
        throw "$path returned unexpected X-Instance-ID '$instance'."
    }
    return $instance
}

$config = docker compose config --format json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration is invalid.' }
foreach ($name in @('api_a', 'api_b', 'api_c', 'db')) {
    if ($config.services.$name.ports) {
        throw "$name has a published host port; only frontend may be public."
    }
}
if (-not $config.services.frontend.ports) {
    throw 'The frontend has no published single-entry port.'
}

$seen = 1..24 | ForEach-Object { Request '/health' }
foreach ($name in @('api-a', 'api-b', 'api-c')) {
    if ($name -notin $seen) { throw "Round Robin did not reach $name." }
}
Write-Host "Three instances through one public port: $((($seen | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))"

docker compose kill api_b | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not stop api_b.' }
try {
    Start-Sleep -Seconds 4
    $afterFailure = 1..30 | ForEach-Object { Request '/api/tests' }
    if ('api-b' -in $afterFailure) {
        throw 'A request was routed to the stopped instance.'
    }
    Write-Host 'Thirty new GET requests stayed on healthy instances without 5xx.'
}
finally {
    docker compose start api_b | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restore api_b.' }
}

$restored = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        $recent = 1..6 | ForEach-Object { Request '/health' }
        if ('api-b' -in $recent) { $restored = $true; break }
    } catch { }
    Start-Sleep -Seconds 1
}
if (-not $restored) { throw 'api_b was not returned to the upstream pool.' }

Write-Host 'PASS: one public entry, three ready instances, automatic failure exclusion and recovery.'
