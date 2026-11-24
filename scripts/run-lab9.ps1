[CmdletBinding()]
param(
    [int]$DurationSeconds = 10,
    [int]$Vus = 5,
    [int]$Runs = 1,
    [int]$QuestionCount = 30,
    [int]$OptionsPerQuestion = 4
)
$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 1 -or $Vus -lt 1 -or $Runs -lt 1 -or $QuestionCount -lt 2 -or $OptionsPerQuestion -lt 2) {
    throw 'DurationSeconds, Vus, Runs must be positive; QuestionCount and OptionsPerQuestion must be at least 2.'
}
$root = (Get-Location).Path
while ($root -and -not (Test-Path (Join-Path $root 'docker-compose.yml'))) {
    $parent = Split-Path $root -Parent
    if ($parent -eq $root) { $root = $null } else { $root = $parent }
}
if (-not $root) { throw 'Run from inside the OnlineTesting project folder.' }
Set-Location $root
$compose = @('-f','docker-compose.yml','-f','docker-compose.profiling.yml')
$baseUrl = 'http://localhost:8081'
$results = Join-Path $root 'profiling\results'
New-Item -ItemType Directory -Force -Path $results | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$fixturePath = Join-Path $results "fixture-$stamp.json"
$headers = @{ 'Content-Type' = 'application/json' }

function Invoke-ApiJson([string]$Method, [string]$Path, $Body = $null, $ExtraHeaders = $null) {
    $h = @{}; foreach ($key in $headers.Keys) { $h[$key] = $headers[$key] }
    if ($ExtraHeaders) { foreach ($key in $ExtraHeaders.Keys) { $h[$key] = $ExtraHeaders[$key] } }
    $requestParams = @{ Method = $Method; Uri = "$baseUrl$Path"; Headers = $h; TimeoutSec = 30 }
    if ($null -ne $Body) { $requestParams.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
    Invoke-RestMethod @requestParams
}
function Invoke-Docker([string[]]$DockerArgs) {
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed: docker $($DockerArgs -join ' ')" }
}
function Get-Summary([string]$File, [string]$Mode, [int]$Run) {
    $j = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    [pscustomobject]@{
        mode=$Mode; run=$Run
        requests=[int]$j.metrics.http_reqs.values.count
        rps=[math]::Round([double]$j.metrics.http_reqs.values.rate,2)
        avgMs=[math]::Round([double]$j.metrics.http_req_duration.values.avg,2)
        p95Ms=[math]::Round([double]$j.metrics.http_req_duration.values.'p(95)',2)
        p99Ms=[math]::Round([double]$j.metrics.http_req_duration.values.'p(99)',2)
        errorPct=[math]::Round(100*[double]$j.metrics.http_req_failed.values.rate,3)
        checksPassed=[int]$j.metrics.checks.values.passes
        checksFailed=[int]$j.metrics.checks.values.fails
    }
}

Invoke-Docker (@('compose') + $compose + @('up','-d','--build','api_a','api_b','api_c','frontend','jaeger'))
$deadline = (Get-Date).AddMinutes(3)
do {
    try { $health = Invoke-RestMethod "$baseUrl/health" -TimeoutSec 5; if ($health.status -eq 'healthy') { break } } catch { }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)
if (-not $health -or $health.status -ne 'healthy') { throw 'API did not become healthy within 3 minutes.' }

Write-Host "Creating synthetic test ($QuestionCount questions × $OptionsPerQuestion options)..."
$test = Invoke-ApiJson POST '/api/tests' @{ title="Lab9 profiling $stamp"; description='Synthetic fixture created by the Lab 9 profiling script.' }
$null = Invoke-ApiJson PUT "/api/tests/$($test.id)" @{ title=$test.title; description=$test.description; isPublished=$true }
$questionRows = @()
for ($i = 1; $i -le $QuestionCount; $i++) {
    $q = Invoke-ApiJson POST "/api/tests/$($test.id)/questions" @{ text="Profiling question $i"; order=$i; points=1 }
    $correctOptionId = $null
    for ($o = 1; $o -le $OptionsPerQuestion; $o++) {
        $option = Invoke-ApiJson POST "/api/questions/$($q.id)/options" @{ text="Option $o for question $i"; isCorrect=($o -eq 1) }
        if ($o -eq 1) { $correctOptionId = $option.id }
    }
    $questionRows += [pscustomobject]@{ questionId=$q.id; optionId=$correctOptionId }
}
$attempt = Invoke-ApiJson POST "/api/tests/$($test.id)/attempts"
$attemptHeaders = @{ 'X-Attempt-Token' = [string]$attempt.accessToken; 'Content-Type'='application/json' }
foreach ($q in $questionRows) {
    $null = Invoke-ApiJson PUT "/api/attempts/$($attempt.attemptId)/answers" @{ questionId=$q.questionId; selectedOptionId=$q.optionId } $attemptHeaders
}
$fixture = [pscustomobject]@{ createdAt=(Get-Date).ToString('o'); testId=$test.id; attemptId=$attempt.attemptId; questionCount=$QuestionCount; optionsPerQuestion=$OptionsPerQuestion }
$fixture | ConvertTo-Json | Set-Content -LiteralPath $fixturePath -Encoding utf8

if (-not (& docker image inspect grafana/k6:1.5.0 2>$null)) { Invoke-Docker @('pull','grafana/k6:1.5.0') }
$attemptToken = [string]$attempt.accessToken
$summaryRows = @()
foreach ($mode in @('single','split')) {
    for ($run = 1; $run -le $Runs; $run++) {
        $summaryName = "$mode-$run-$stamp.json"
        $summaryPath = Join-Path $results $summaryName
        $mountRoot = $root.Replace('\','/')
        $dockerArgs = @('run','--rm','--add-host=host.docker.internal:host-gateway',
            '--mount',"type=bind,source=$mountRoot,target=/work",'-w','/work',
            '-e',"BASE_URL=http://host.docker.internal:8081",'-e',"ATTEMPT_ID=$($attempt.attemptId)",
            '-e',"ATTEMPT_TOKEN=$attemptToken",'-e',"QUERY_MODE=$mode",'-e',"VUS=$Vus",'-e',"DURATION=${DurationSeconds}s",
            'grafana/k6:1.5.0','run',"--summary-export=/work/profiling/results/$summaryName",'/work/profiling/lab9.js')
        $statsPath = Join-Path $results "$mode-$run-$stamp-docker-stats.csv"
        "timestamp,container,cpu,memory" | Set-Content -LiteralPath $statsPath -Encoding utf8
        $stats = Start-Job -ArgumentList $statsPath -ScriptBlock {
            param($output)
            while ($true) {
                $time = (Get-Date).ToString('o')
                $lines = & docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}}' 2>$null
                foreach ($line in $lines) { Add-Content -LiteralPath $output -Value "$time,$line" }
                Start-Sleep -Seconds 1
            }
        }
        try { Invoke-Docker $dockerArgs } finally { Stop-Job $stats -ErrorAction SilentlyContinue | Out-Null; Remove-Job $stats -Force -ErrorAction SilentlyContinue }
        $summaryRows += Get-Summary $summaryPath $mode $run
        Write-Host "Finished $mode run $run/$Runs"
    }
}
$summaryRows | Export-Csv -LiteralPath (Join-Path $results "summary-$stamp.csv") -NoTypeInformation -Encoding utf8

$id = [int]$attempt.attemptId
$tokenSql = ([string]$attempt.accessToken).Replace("'","''")
$plan = @"
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT a.*, t.*, q.*, o.*, ans.*
FROM "TestAttempts" AS a
JOIN "Tests" AS t ON t."Id" = a."TestId"
LEFT JOIN "Questions" AS q ON q."TestId" = t."Id"
LEFT JOIN "AnswerOptions" AS o ON o."QuestionId" = q."Id"
LEFT JOIN "StudentAnswers" AS ans ON ans."TestAttemptId" = a."Id" AND ans."QuestionId" = q."Id"
WHERE a."Id" = $id AND a."AccessToken" = '$tokenSql';
"@
$planText = & docker compose @compose exec -T db psql -U app -d online_testing -X -t -A -c $plan 2>&1
if ($LASTEXITCODE -ne 0) { throw "Single-query EXPLAIN failed: $planText" }
$planText | Set-Content -LiteralPath (Join-Path $results "single-explain-$stamp.json") -Encoding utf8
$splitPlans = @(
    @"
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT a.*, t.* FROM "TestAttempts" a JOIN "Tests" t ON t."Id"=a."TestId" WHERE a."Id"=$id AND a."AccessToken"='$tokenSql';
"@,
    @"
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT q.*, o.* FROM "Questions" q LEFT JOIN "AnswerOptions" o ON o."QuestionId"=q."Id" WHERE q."TestId"=(SELECT "TestId" FROM "TestAttempts" WHERE "Id"=$id AND "AccessToken"='$tokenSql');
"@,
    @"
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT ans.* FROM "StudentAnswers" ans WHERE ans."TestAttemptId"=$id;
"@)
$splitText = foreach ($statement in $splitPlans) {
    $output = & docker compose @compose exec -T db psql -U app -d online_testing -X -t -A -c $statement 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Split-query EXPLAIN failed: $output" }
    $output
}
$splitText | Set-Content -LiteralPath (Join-Path $results "split-explain-$stamp.json") -Encoding utf8
$summaryRows | Format-Table -AutoSize
Write-Host "PASS Lab 9 runs complete. Artifacts: $results" -ForegroundColor Green
Write-Host "Fixture test ID $($test.id), attempt ID $($attempt.attemptId). Delete test $($test.id) after reviewing results if desired."
Write-Host 'Jaeger UI: http://localhost:16686 (find span lab9.attempt.read).'
