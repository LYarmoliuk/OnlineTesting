param(
    [string]$BaseUrl = 'http://localhost:8081',
    [string]$Path = '/api/benchmark',
    [int]$Requests = 240,
    [int]$Concurrency = 24,
    [string]$Label = 'lab3',
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($Requests -lt 1 -or $Concurrency -lt 1) {
    throw 'Requests and Concurrency must be positive.'
}

$uri = $BaseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/')

# Warm up the HTTP client, Nginx and upstream DNS before timing the run.
for ($i = 0; $i -lt 12; $i++) {
    try { Invoke-WebRequest -Uri $uri -TimeoutSec 10 -SkipHttpErrorCheck | Out-Null }
    catch { }
}

$wall = [Diagnostics.Stopwatch]::StartNew()
$results = @(1..$Requests | ForEach-Object -Parallel {
    $ProgressPreference = 'SilentlyContinue'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $using:uri -TimeoutSec 10 -SkipHttpErrorCheck
        [pscustomobject]@{
            Status = [int]$response.StatusCode
            Instance = [string]$response.Headers['X-Instance-ID']
            Algorithm = [string]$response.Headers['X-Lab3-Algorithm']
            DurationMs = $watch.Elapsed.TotalMilliseconds
        }
    }
    catch {
        [pscustomobject]@{
            Status = 0
            Instance = ''
            Algorithm = ''
            DurationMs = $watch.Elapsed.TotalMilliseconds
        }
    }
} -ThrottleLimit $Concurrency)
$wall.Stop()

$successes = @($results | Where-Object Status -eq 200)
$latencies = @($successes | ForEach-Object DurationMs | Sort-Object)
$p99 = if ($latencies.Count -gt 0) {
    $latencies[[math]::Ceiling($latencies.Count * 0.99) - 1]
} else { 0 }
$distribution = [ordered]@{ 'api-a' = 0; 'api-b' = 0; 'api-c' = 0 }
foreach ($result in $successes) {
    if ($distribution.Contains($result.Instance)) {
        $distribution[$result.Instance]++
    }
}

$algorithmNames = @($successes | ForEach-Object Algorithm | Where-Object { $_ } | Select-Object -Unique)
$summary = [pscustomobject]@{
    label = $Label
    timestamp = (Get-Date).ToString('o')
    algorithm = $algorithmNames -join ','
    requests = $Requests
    concurrency = $Concurrency
    successful = $successes.Count
    failed = $Requests - $successes.Count
    durationSeconds = [math]::Round($wall.Elapsed.TotalSeconds, 3)
    rps = if ($wall.Elapsed.TotalSeconds -gt 0) { [math]::Round($successes.Count / $wall.Elapsed.TotalSeconds, 2) } else { 0 }
    p99Ms = [math]::Round($p99, 2)
    instances = $distribution
}

if ($OutFile) {
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutFile -Encoding utf8
}
Write-Host "$Label`: success=$($summary.successful)/$Requests, RPS=$($summary.rps), p99=$($summary.p99Ms) ms, api-a=$($distribution['api-a']), api-b=$($distribution['api-b']), api-c=$($distribution['api-c'])"
$summary
