param(
    [string]$BaseUrl = 'http://localhost:8081',
    [int]$Requests = 240,
    [int]$Concurrency = 24,
    [string]$OutputFile = 'docs/lab3-results.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$originalDelay = [Environment]::GetEnvironmentVariable('LAB3_DELAY_MS', 'Process')

function Compose([string[]]$arguments) {
    & docker compose @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker compose $($arguments -join ' ') failed." }
}

function Restart-NginxWorkers {
    # Refresh upstream DNS and failure counters after changing the replica count.
    Compose -arguments @('exec', '-T', 'frontend', 'nginx', '-s', 'reload')
}

function Use-NginxConfig([string]$name, [string]$expectedHeader) {
    $frontendId = (& docker compose ps -q frontend).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $frontendId) { throw 'Frontend container is not running.' }
    $source = Join-Path $projectRoot "frontend/$name"
    & docker cp $source "${frontendId}:/etc/nginx/conf.d/default.conf" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not copy $name into Nginx." }
    Compose -arguments @('exec', '-T', 'frontend', 'nginx', '-t')
    Compose -arguments @('exec', '-T', 'frontend', 'nginx', '-s', 'reload')
    for ($i = 0; $i -lt 15; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "$BaseUrl/api/benchmark" -TimeoutSec 5 -SkipHttpErrorCheck
            if ([string]$response.Headers['X-Lab3-Algorithm'] -eq $expectedHeader) { return }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    throw "Nginx did not activate $expectedHeader."
}

function Invoke-Lab3Measurement([string]$label) {
    & (Join-Path $PSScriptRoot 'measure-lab3.ps1') -BaseUrl $BaseUrl -Requests $Requests -Concurrency $Concurrency -Label $label
}

Push-Location $projectRoot
try {
    $env:LAB3_DELAY_MS = '0'
    Compose -arguments @('up', '-d', '--no-build', '--force-recreate', 'api_b')
    Compose -arguments @('start', 'api_a', 'api_b', 'api_c')
    Use-NginxConfig 'nginx.conf' 'round-robin'

    Compose -arguments @('stop', 'api_b', 'api_c')
    Restart-NginxWorkers
    Start-Sleep -Seconds 4
    $one = Invoke-Lab3Measurement 'scale-1'

    Compose -arguments @('start', 'api_b')
    Restart-NginxWorkers
    Start-Sleep -Seconds 4
    $two = Invoke-Lab3Measurement 'scale-2'

    Compose -arguments @('start', 'api_c')
    Restart-NginxWorkers
    Start-Sleep -Seconds 4
    $three = Invoke-Lab3Measurement 'scale-3'

    $env:LAB3_DELAY_MS = '250'
    Compose -arguments @('up', '-d', '--no-build', '--force-recreate', 'api_b')
    Restart-NginxWorkers
    Start-Sleep -Seconds 4
    $roundRobin = Invoke-Lab3Measurement 'slow-b-round-robin'

    Use-NginxConfig 'nginx.least.conf' 'least-connections'
    $leastConnections = Invoke-Lab3Measurement 'slow-b-least-connections'

    $all = @($one, $two, $three, $roundRobin, $leastConnections)
    if (@($all | Where-Object failed -gt 0).Count -gt 0) {
        throw 'A benchmark run returned failed HTTP requests.'
    }
    if ($one.instances['api-b'] -ne 0 -or $one.instances['api-c'] -ne 0 -or
        $two.instances['api-c'] -ne 0 -or $three.instances['api-c'] -eq 0) {
        throw 'Instance distribution did not match the 1/2/3 node configurations.'
    }

    $result = [pscustomobject]@{
        environment = 'Docker Compose on one developer computer; same shared PostgreSQL'
        requestPath = '/api/benchmark'
        note = 'This synthetic read-only workload measures this computer, not production capacity.'
        runs = $all
    }
    $target = Join-Path $projectRoot $OutputFile
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $target -Encoding utf8
    Write-Host "PASS: five benchmark runs saved to $target"
}
finally {
    if ($null -eq $originalDelay) {
        Remove-Item Env:LAB3_DELAY_MS -ErrorAction SilentlyContinue
    } else {
        $env:LAB3_DELAY_MS = $originalDelay
    }
    try {
        Compose -arguments @('start', 'api_b', 'api_c')
        Compose -arguments @('up', '-d', '--no-build', '--force-recreate', 'api_b')
        Use-NginxConfig 'nginx.conf' 'round-robin'
    } finally {
        Pop-Location
    }
}


