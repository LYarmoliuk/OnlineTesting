param(
    [string]$BaseUrl = 'http://localhost:8080'
)

$ErrorActionPreference = 'Stop'

function Request($method, $path, $body = $null, $token = $null, $expected = 200) {
    $headers = @{}
    if ($token) { $headers['X-Attempt-Token'] = $token }
    $parameters = @{
        Uri = "$BaseUrl$path"
        Method = $method
        Headers = $headers
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = ConvertTo-Json -InputObject $body -Compress -Depth 10
    }
    $response = Invoke-WebRequest @parameters
    if ($response.StatusCode -ne $expected) {
        throw "$method $path returned $($response.StatusCode), expected $expected`: $($response.Content)"
    }
    Write-Host "$method $path => $($response.StatusCode)"
    if ($response.Content -and $response.Content.TrimStart() -match '^[\{\[]') {
        return $response.Content | ConvertFrom-Json
    }
}

try {
    Request GET '/health' | Out-Null

    $test = Request POST '/api/tests' @{ title = "Vlad stateless check $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"; description = 'Standalone part verification' } $null 201
    $question = Request POST "/api/tests/$($test.id)/questions" @{ text = '2 + 2?'; order = 1; points = 5 } $null 201
    $correct = Request POST "/api/questions/$($question.id)/options" @{ text = '4'; isCorrect = $true } $null 201
    Request POST "/api/questions/$($question.id)/options" @{ text = '5'; isCorrect = $false } $null 201 | Out-Null
    Request PUT "/api/tests/$($test.id)" @{ title = $test.title; description = $test.description; isPublished = $true } | Out-Null

    $attempt = Request POST "/api/tests/$($test.id)/attempts" $null $null 201
    $path = "/api/attempts/$($attempt.attemptId)"
    $token = [string]$attempt.accessToken
    $body = @{ questionId = $question.id; selectedOptionId = $correct.id } | ConvertTo-Json -Compress

    # Concurrent writes to one attempt must serialize through PostgreSQL.
    $statuses = 1..8 | ForEach-Object -Parallel {
        $response = Invoke-WebRequest -Uri "$using:BaseUrl$using:path/answers" -Method PUT -Headers @{ 'X-Attempt-Token' = $using:token } -ContentType 'application/json' -Body $using:body -SkipHttpErrorCheck
        $response.StatusCode
    } -ThrottleLimit 8
    if (($statuses | Where-Object { $_ -ne 204 }).Count -gt 0 -or $statuses.Count -ne 8) {
        throw "Concurrent writes failed: $($statuses -join ', ')"
    }
    Write-Host 'Eight concurrent answer writes => all 204'

    $saved = Request GET $path $null $token
    if ($saved.questions.Count -ne 1 -or $saved.questions[0].selectedOptionId -ne $correct.id) {
        throw 'Saved answer was not read back correctly.'
    }

    docker compose restart api | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restart the API container.' }
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $health = Invoke-WebRequest -Uri "$BaseUrl/health" -TimeoutSec 2 -SkipHttpErrorCheck
            if ($health.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'API did not become ready after restart.' }
    $afterRestart = Request GET $path $null $token
    if ($afterRestart.questions[0].selectedOptionId -ne $correct.id) {
        throw 'Answer was lost after API restart.'
    }

    $result = Request POST "$path/submit" $null $token
    if ($result.score -ne 5 -or $result.answeredQuestions -ne 1) { throw 'Wrong score or answer count.' }
    $repeated = Request POST "$path/submit" $null $token
    $completionDriftMs = [math]::Abs(($repeated.completedAt - $result.completedAt).TotalMilliseconds)
    if ($repeated.score -ne $result.score -or $completionDriftMs -gt 1) {
        throw "Repeated submission changed the result: first score=$($result.score), time=$($result.completedAt); second score=$($repeated.score), time=$($repeated.completedAt)"
    }
    Request PUT "$path/answers" @{ questionId = $question.id; selectedOptionId = $correct.id } $token 409 | Out-Null
    $storedResult = Request GET "$path/result" $null $token
    if ($storedResult.score -ne 5) { throw 'Stored result was not read back correctly.' }

    Write-Host "PASS: Vlad part works standalone; test=$($test.id), attempt=$($attempt.attemptId)"
}
catch {
    Write-Error $_
    exit 1
}
