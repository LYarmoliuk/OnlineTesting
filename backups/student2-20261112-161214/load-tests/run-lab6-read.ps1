param([ValidateRange(5,300)][int]$StageSeconds = 30,
      [string]$BaseUrl = 'http://host.docker.internal:8081')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results\lab6'
New-Item -ItemType Directory -Force $results | Out-Null
$rows = @()
foreach ($mode in @('primary','replica')) {
    foreach ($vus in @(10,25,50,100,200)) {
        $file = "$mode-$vus.json"
        docker run --rm --cpus 1 --memory 512m -v "${root}:/src:ro" -v "${results}:/results" grafana/k6:1.5.0 run --vus $vus --duration "${StageSeconds}s" --summary-trend-stats 'avg,p(50),p(95),p(99)' --summary-export "/results/$file" -e "BASE_URL=$BaseUrl" -e EXPECT_CACHE=BYPASS -e "LAB6_PRIMARY_ONLY=$(if ($mode -eq 'primary') { '1' } else { '0' })" /src/read.js | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "k6 failed: $mode $vus" }
        $metrics = (Get-Content (Join-Path $results $file) -Raw | ConvertFrom-Json).metrics
        $rows += [pscustomobject]@{
            mode=$mode; vus=$vus; rps=[math]::Round($metrics.http_reqs.rate,2)
            p95Ms=[math]::Round($metrics.http_req_duration.'p(95)',2)
            p99Ms=[math]::Round($metrics.http_req_duration.'p(99)',2)
            errorPct=[math]::Round(100*$metrics.http_req_failed.value,2)
            failedChecks=[int]$metrics.checks.fails
        }
    }
}
$rows | ConvertTo-Json | Set-Content (Join-Path $results 'summary.json') -Encoding utf8
& (Join-Path $root 'render-lab6-read.ps1') -Summary (Join-Path $results 'summary.json') -StageSeconds $StageSeconds -Output (Join-Path (Split-Path $root -Parent) 'docs/lab6-read-scaling.md')
$rows | Format-Table -AutoSize
