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

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$killer = Start-Job -ArgumentList $projectRoot -ScriptBlock {
    param($root)
    Set-Location $root
    Start-Sleep -Milliseconds 800
    docker compose kill api_b 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop api_b.' }
    [datetime]::UtcNow
}
try {
    $traffic = @(1..400 | ForEach-Object -Parallel {
        $started = [datetime]::UtcNow
        try {
            $response = Invoke-WebRequest -Uri "$using:BaseUrl/api/tests" -TimeoutSec 10 -SkipHttpErrorCheck
            [pscustomobject]@{
                Started = $started
                Status = [int]$response.StatusCode
                Instance = [string]$response.Headers['X-Instance-ID']
            }
        }
        catch {
            [pscustomobject]@{ Started = $started; Status = 0; Instance = '' }
        }
    } -ThrottleLimit 24)
    $killer | Wait-Job | Out-Null
    if ($killer.State -ne 'Completed') { throw "Node stop failed: $(($killer.ChildJobs[0].JobStateInfo.Reason))" }
    $killedAt = Receive-Job $killer
    $before = @($traffic | Where-Object { $_.Started -lt $killedAt })
    $after = @($traffic | Where-Object { $_.Started -ge $killedAt })
    if ($before.Count -eq 0 -or $after.Count -eq 0) {
        throw 'The node stop did not occur during the request stream.'
    }
    $failures = @($traffic | Where-Object { $_.Status -ne 200 -or $_.Instance -notin @('api-a', 'api-b', 'api-c') })
    if ($failures.Count -gt 0) {
        throw "During node stop, $($failures.Count)/$($traffic.Count) requests failed."
    }
    if (@($after | Where-Object Instance -eq 'api-b').Count -gt 0) {
        throw 'Requests started after api_b stopped were routed to it.'
    }
    Write-Host "Live failover: $($traffic.Count) requests, $($before.Count) started before stop, $($after.Count) after stop, 0 failures."
}
finally {
    $killer | Stop-Job -ErrorAction SilentlyContinue
    $killer | Remove-Job -Force -ErrorAction SilentlyContinue
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
