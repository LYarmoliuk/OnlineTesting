param(
    [string]$BaseUrl = 'http://host.docker.internal:8081',
    [string]$Image = 'grafana/k6:1.5.0',
    [ValidateRange(2, 600)][int]$StageSeconds = 30,
    [switch]$Smoke
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root $(if ($Smoke) { 'results\student2\smoke' } else { 'results\student2' })
New-Item -ItemType Directory -Force -Path $results | Out-Null
$levels = if ($Smoke) { @(1) } else { @(10, 25, 50, 100, 200) }
$duration = if ($Smoke) { '2s' } else { "${StageSeconds}s" }
$localUrl = $BaseUrl.Replace('host.docker.internal', 'localhost').TrimEnd('/')
$testId = $null
$rows = @()

function Invoke-JsonPost([string]$url, [object]$body) {
    return Invoke-RestMethod $url -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json)
}

function Invoke-K6([string]$scenario, [int]$nodes, [int]$vus, [string]$runDuration, [string]$outputName) {
    $arguments = @(
        'run', '--vus', $vus, '--duration', $runDuration,
        '--summary-trend-stats', 'avg,p(50),p(95),p(99)',
        '--summary-export', "/results/$outputName.json",
        '-e', "BASE_URL=$BaseUrl", '-e', "TEST_ID=$testId",
        '-e', "QUESTION_ID=$questionId", '-e', "OPTION_ID=$optionId",
        '-e', "SINGLE_NODE=$(if ($nodes -eq 1) { '1' } else { '0' })",
        "/src/$scenario.js"
    )
    & docker run --rm --cpus 1 --memory 512m -v "${root}:/src:ro" -v "${results}:/results" $Image @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "k6 failed for $scenario, $nodes nodes, $vus VUs." }
    if ($outputName -eq 'warmup') { return $null }
    $data = Get-Content (Join-Path $results "$outputName.json") -Raw | ConvertFrom-Json
    $m = $data.metrics
    if ($Smoke -and $m.checks.fails -gt 0) { throw "Checks failed for $outputName." }
    return [pscustomobject]@{
        scenario = $scenario
        nodes = $nodes
        vus = $vus
        targetSeconds = if ($Smoke) { 2 } else { $StageSeconds }
        elapsedSeconds = if ($m.http_reqs.rate -gt 0) { [math]::Round($m.http_reqs.count / $m.http_reqs.rate, 2) } else { 0 }
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
    $name = 'Lab5-workflow-' + [guid]::NewGuid().ToString('N')
    $test = Invoke-JsonPost "$localUrl/api/tests" @{ title = $name; description = 'Temporary load fixture' }
    $testId = [int]$test.id
    $question = Invoke-JsonPost "$localUrl/api/tests/$testId/questions" @{ text = 'One plus zero?'; order = 1; points = 1 }
    $questionId = [int]$question.id
    $correct = Invoke-JsonPost "$localUrl/api/questions/$questionId/options" @{ text = 'One'; isCorrect = $true }
    $optionId = [int]$correct.id
    Invoke-JsonPost "$localUrl/api/questions/$questionId/options" @{ text = 'Two'; isCorrect = $false } | Out-Null
    Invoke-RestMethod "$localUrl/api/tests/$testId" -Method Put -ContentType 'application/json' -Body (@{ title=$name; description='Temporary load fixture'; isPublished=$true } | ConvertTo-Json) | Out-Null

    foreach ($nodes in @(1, 3)) {
        $ready = $false
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            try {
                $health = Invoke-WebRequest "$localUrl/health" -TimeoutSec 5
                if ($health.StatusCode -eq 200) { $ready = $true; break }
            } catch { }
            Start-Sleep -Seconds 2
        }
        if (-not $ready) { throw "API was not ready with $nodes nodes." }
        Start-Sleep -Seconds 5
        foreach ($scenario in @('write', 'workflow')) {
            Invoke-K6 $scenario $nodes 2 '3s' 'warmup' | Out-Null
            foreach ($vus in $levels) {
                $rows += Invoke-K6 $scenario $nodes $vus $duration "$scenario-$nodes-$vus"
            }
        }
    }
}
finally {
    if ($testId) {
        $sql = "DELETE FROM ""StudentAnswers"" WHERE ""TestAttemptId"" IN (SELECT ""Id"" FROM ""TestAttempts"" WHERE ""TestId""=$testId); DELETE FROM ""TestAttempts"" WHERE ""TestId""=$testId; DELETE FROM ""Tests"" WHERE ""Id""=$testId;"
        & docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app -d online_testing -c $sql | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "Manual cleanup needed for test $testId." }
    }
}

$rows | Format-Table -AutoSize
$rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $results 'write-workflow-summary.json') -Encoding utf8
$reportName = if ($Smoke) { 'lab5-write-workflow-smoke.md' } else { 'lab5-write-workflow.md' }
& (Join-Path $root 'render-write-workflow.ps1') -Summary (Join-Path $results 'write-workflow-summary.json') -Output (Join-Path (Split-Path $root -Parent) "docs/$reportName")
Write-Host "Results: $results"
