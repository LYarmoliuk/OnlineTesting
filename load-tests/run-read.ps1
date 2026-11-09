param(
    [string]$BaseUrl = 'http://host.docker.internal:8081',
    [string]$Image = 'grafana/k6:1.5.0',
    [ValidateRange(2, 600)][int]$StageSeconds = 8,
    [switch]$Smoke
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$resultFolder = if ($Smoke) { 'results\student1\smoke' } else { 'results\student1' }
$results = Join-Path $root $resultFolder
New-Item -ItemType Directory -Force -Path $results | Out-Null
$levels = if ($Smoke) { @(1) } else { @(10, 25, 50, 100, 200) }
$duration = if ($Smoke) { '2s' } else { "${StageSeconds}s" }
$redisStopped = $false
$rows = @()

function Get-DbReads {
    $value = & docker compose exec -T db psql -U app -d online_testing -Atc "SELECT tup_returned FROM pg_stat_database WHERE datname='online_testing'"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read PostgreSQL statistics.' }
    return [long]($value | Select-Object -Last 1)
}

function Invoke-K6([string]$mode, [int]$vus, [string]$runDuration, [string]$expected, [string]$outputName) {
    $out = "/results/$outputName.json"
    $arguments = @(
        'run', '--vus', $vus, '--duration', $runDuration,
        '--summary-trend-stats', 'avg,p(50),p(95),p(99)',
        '--summary-export', $out,
        '-e', "BASE_URL=$BaseUrl", '-e', "EXPECT_CACHE=$expected",
        '/src/read.js'
    )
    & docker run --rm --cpus 1 --memory 512m -v "${root}:/src:ro" -v "${results}:/results" $Image @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "k6 failed for $mode at $vus VUs." }
    if ($outputName -eq 'warmup') { return $null }
    $data = Get-Content (Join-Path $results "$outputName.json") -Raw | ConvertFrom-Json
    $m = $data.metrics
    if ($Smoke -and $m.checks.fails -gt 0) { throw "Checks failed for $outputName." }
    return [pscustomobject]@{
        mode = $mode
        vus = $vus
        requests = [int]$m.http_reqs.count
        targetSeconds = if ($Smoke) { 2 } else { $StageSeconds }
        elapsedSeconds = if ($m.http_reqs.rate -gt 0) { [math]::Round($m.http_reqs.count / $m.http_reqs.rate, 2) } else { 0 }
        hitPct = if ($m.http_reqs.count -gt 0) { [math]::Round(100 * [int]$m.cache_hits.count / $m.http_reqs.count, 2) } else { 0 }
        rps = [math]::Round($m.http_reqs.rate, 2)
        avgMs = [math]::Round($m.http_req_duration.avg, 2)
        p50Ms = [math]::Round($m.http_req_duration.'p(50)', 2)
        p95Ms = [math]::Round($m.http_req_duration.'p(95)', 2)
        p99Ms = [math]::Round($m.http_req_duration.'p(99)', 2)
        errorPct = [math]::Round(100 * $m.http_req_failed.value, 2)
        checkFailures = [int]$m.checks.fails
    }
}

try {
    foreach ($mode in @('warm', 'disabled')) {
        if ($mode -eq 'disabled') {
            & docker compose stop redis | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Cannot stop Redis.' }
            $redisStopped = $true
        } else {
            $url = $BaseUrl.Replace('host.docker.internal', 'localhost')
            Invoke-WebRequest "$url/api/tests" -SkipHttpErrorCheck | Out-Null
        }
        $expected = if ($mode -eq 'warm') { 'HIT' } else { 'BYPASS' }
        Invoke-K6 $mode 2 '3s' $expected 'warmup' | Out-Null
        $before = Get-DbReads
        foreach ($vus in $levels) {
            if ($mode -eq 'warm') {
                & docker compose exec -T redis redis-cli DEL 'online-testing:lab4:tests:list:v1' | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not reset the Redis key.' }
                $url = $BaseUrl.Replace('host.docker.internal', 'localhost')
                Invoke-WebRequest "$url/api/tests" -SkipHttpErrorCheck | Out-Null
            }
            $rows += Invoke-K6 $mode $vus $duration $expected "$mode-$vus"
        }
        $delta = (Get-DbReads) - $before
        Set-Content (Join-Path $results "$mode-db-reads.txt") $delta
    }
}
finally {
    if ($redisStopped) { & docker compose start redis | Out-Null }
}

$rows | Format-Table -AutoSize
$rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $results 'read-summary.json') -Encoding utf8
$reportName = if ($Smoke) { 'lab5-read-smoke.md' } else { 'lab5-read.md' }
& (Join-Path $root 'render-read.ps1') -Summary (Join-Path $results 'read-summary.json') -Output (Join-Path (Split-Path $root -Parent) "docs/$reportName")
Write-Host "Results: $results"
