param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$CacheKey,
    [int]$Pairs = 10,
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($Pairs -lt 1) { throw 'Pairs must be positive.' }

function Measure-Request {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + $Path) -TimeoutSec 15 -SkipHttpErrorCheck
    $watch.Stop()
    if ($response.StatusCode -ne 200) { throw "$Path returned $($response.StatusCode)." }
    [pscustomobject]@{
        cache = [string]$response.Headers['X-Cache']
        instance = [string]$response.Headers['X-Instance-ID']
        durationMs = [math]::Round($watch.Elapsed.TotalMilliseconds, 2)
    }
}

# Warm the application and HTTP client before measuring Redis misses and hits.
Measure-Request | Out-Null
$samples = for ($i = 1; $i -le $Pairs; $i++) {
    docker compose -p $Project exec -T redis redis-cli DEL "online-testing:lab4:$CacheKey" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not clear the Redis key.' }
    $cold = Measure-Request
    $hot = Measure-Request
    if ($cold.cache -ne 'MISS' -or $hot.cache -ne 'HIT') {
        throw "Pair $i returned $($cold.cache) then $($hot.cache), expected MISS then HIT."
    }
    [pscustomobject]@{ pair = $i; cold = $cold; hot = $hot }
}

$result = [pscustomobject]@{
    timestamp = (Get-Date).ToString('o')
    project = $Project
    path = $Path
    cacheKey = $CacheKey
    pairs = $Pairs
    coldAverageMs = [math]::Round((@($samples | ForEach-Object { $_.cold.durationMs } | Measure-Object -Average)[0].Average), 2)
    hotAverageMs = [math]::Round((@($samples | ForEach-Object { $_.hot.durationMs } | Measure-Object -Average)[0].Average), 2)
    samples = @($samples)
}
if ($OutFile) {
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding utf8
}
Write-Host "$Path`: cold average=$($result.coldAverageMs) ms, hot average=$($result.hotAverageMs) ms ($Pairs pairs)"
$result
