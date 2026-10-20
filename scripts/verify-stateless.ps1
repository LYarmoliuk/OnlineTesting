param(
    [switch]$SkipFailureScenario
)

$ErrorActionPreference = 'Stop'
$apiA = 'http://localhost:8080'
$apiB = 'http://localhost:8082'
$proxy = 'http://localhost:8081'

function Request($base, $method, $path, $body = $null, $token = $null, $expected = 200, $instance = $null) {
    $headers = @{}
    if ($token) { $headers['X-Attempt-Token'] = $token }
    $parameters = @{
        Uri = "$base$path"
        Method = $method
        Headers = $headers
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = ConvertTo-Json -InputObject $body -Depth 10 -Compress
    }
    $response = Invoke-WebRequest @parameters
    if ($response.StatusCode -ne $expected) {
        throw "$method $base$path returned $($response.StatusCode), expected $expected`: $($response.Content)"
    }
    $actualInstance = [string]$response.Headers['X-Instance-ID']
    if ($instance -and $actualInstance -ne $instance) {
        throw "$method $path was served by '$actualInstance', expected '$instance'"
    }
    Write-Host "$method $path => $($response.StatusCode), X-Instance-ID=$actualInstance"
    if ($response.Content -and $response.Content.TrimStart() -match '^[\{\[]') {
        return $response.Content | ConvertFrom-Json
    }
}

try {
    Request $apiA GET '/health' $null $null 200 'api-a' | Out-Null
    Request $apiB GET '/health' $null $null 200 'api-b' | Out-Null

    $test = Request $apiA POST '/api/tests' @{ title = "Stateless verification $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"; description = 'Automated resilience scenario' } $null 201 'api-a'
    $question = Request $apiB POST "/api/tests/$($test.id)/questions" @{ text = '2 + 2?'; order = 1; points = 5 } $null 201 'api-b'
    $correct = Request $apiA POST "/api/questions/$($question.id)/options" @{ text = '4'; isCorrect = $true } $null 201 'api-a'
    Request $apiB POST "/api/questions/$($question.id)/options" @{ text = '5'; isCorrect = $false } $null 201 'api-b' | Out-Null
    Request $apiA PUT "/api/tests/$($test.id)" @{ title = $test.title; description = $test.description; isPublished = $true } $null 200 'api-a' | Out-Null

    $attempt = Request $apiA POST "/api/tests/$($test.id)/attempts" $null $null 201 'api-a'
    $path = "/api/attempts/$($attempt.attemptId)"
    $readB = Request $apiB GET $path $null $attempt.accessToken 200 'api-b'
    if ($readB.status -ne 'InProgress' -or $readB.questions.Count -ne 1) { throw 'Instance B did not see the attempt.' }

    Request $apiB PUT "$path/answers" @{ questionId = $question.id; selectedOptionId = $correct.id } $attempt.accessToken 204 'api-b' | Out-Null
    $readA = Request $apiA GET $path $null $attempt.accessToken 200 'api-a'
    if ($readA.questions[0].selectedOptionId -ne $correct.id) { throw 'Instance A did not see the saved answer.' }

    if (-not $SkipFailureScenario) {
        # Hold the attempt row in PostgreSQL so a request to api_a is in flight
        # when that container is killed. PostgreSQL must roll back that request.
        $composeFile = Join-Path (Get-Location).Path 'docker-compose.yml'
        $lockSql = "BEGIN; SELECT 1 FROM `"TestAttempts`" WHERE `"Id`" = $($attempt.attemptId) FOR UPDATE; SELECT pg_sleep(15); ROLLBACK;"
        $lockJob = Start-Job -ArgumentList $composeFile, $lockSql -ScriptBlock {
            param($file, $sql)
            docker compose -f $file exec -T db psql -U app -d online_testing -c $sql
        }
        Start-Sleep -Seconds 2
        $requestJob = Start-Job -ArgumentList $apiA, $path, $attempt.accessToken, $question.id, $correct.id -ScriptBlock {
            param($base, $attemptPath, $token, $questionId, $optionId)
            $body = @{ questionId = $questionId; selectedOptionId = $optionId } | ConvertTo-Json -Compress
            try {
                Invoke-WebRequest -Uri "$base$attemptPath/answers" -Method PUT -Headers @{ 'X-Attempt-Token' = $token } -ContentType 'application/json' -Body $body -TimeoutSec 20 | Out-Null
            } catch { }
        }
        $waiting = $false
        for ($i = 0; $i -lt 20; $i++) {
            $lockCount = docker compose exec -T db psql -U app -d online_testing -At -c "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND query LIKE '%TestAttempts%';"
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect PostgreSQL lock waits.' }
            if ([int]$lockCount -gt 0) { $waiting = $true; break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $waiting) { throw 'The api_a request did not reach the row lock.' }
        Write-Host 'api_a has an in-flight request waiting for a PostgreSQL row lock.'

        docker compose kill api_a | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not kill api_a.' }
        try {
            $afterFailure = Request $proxy GET $path $null $attempt.accessToken 200 'api-b'
            if ($afterFailure.questions[0].selectedOptionId -ne $correct.id) { throw 'Answer was lost after api_a failed.' }
        }
        finally {
            Wait-Job $requestJob, $lockJob | Out-Null
            Remove-Job $requestJob, $lockJob
            docker compose start api_a | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not restart api_a.' }
            $ready = $false
            for ($i = 0; $i -lt 30; $i++) {
                try {
                    $health = Invoke-WebRequest -Uri "$apiA/health" -TimeoutSec 2 -SkipHttpErrorCheck
                    if ($health.StatusCode -eq 200) { $ready = $true; break }
                } catch { }
                Start-Sleep -Milliseconds 500
            }
            if (-not $ready) { throw 'api_a did not become ready after restart.' }
        }
    }

    $submitted = Request $apiB POST "$path/submit" $null $attempt.accessToken 200 'api-b'
    if ($submitted.score -ne 5 -or $submitted.answeredQuestions -ne 1) { throw 'Incorrect submitted score.' }
    $result = Request $apiA GET "$path/result" $null $attempt.accessToken 200 'api-a'
    if ($result.score -ne 5) { throw 'Result was not visible on instance A.' }
    Request $apiA PUT "$path/answers" @{ questionId = $question.id; selectedOptionId = $correct.id } $attempt.accessToken 409 'api-a' | Out-Null

    Write-Host "PASS: cross-instance consistency and recovery; test=$($test.id), attempt=$($attempt.attemptId)"
}
catch {
    Write-Error $_
    exit 1
}
