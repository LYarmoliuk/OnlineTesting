param(
    [string]$BaseUrl = 'http://localhost:8081',
    [string]$Project = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$composeArgs = if ($Project) { @('-p', $Project) } else { @() }
$testId = $null
$redisStopped = $false

function Assert-Response($response, $status, $cacheStatus = '') {
    if ($response.StatusCode -ne $status) { throw "Expected HTTP $status, got $($response.StatusCode)." }
    if ($cacheStatus -and [string]$response.Headers['X-Cache'] -ne $cacheStatus) {
        throw "Expected X-Cache: $cacheStatus, got $($response.Headers['X-Cache'])."
    }
}

try {
    $created = Invoke-WebRequest "$BaseUrl/api/tests" -Method Post -ContentType 'application/json' -Body (@{title="Lab4 student2 $([guid]::NewGuid().ToString('N'))";description='cache verification'} | ConvertTo-Json) -SkipHttpErrorCheck
    Assert-Response $created 201
    $testId = ($created.Content | ConvertFrom-Json).id
    $path = "$BaseUrl/api/tests/$testId/questions"
    & docker compose @composeArgs exec -T redis redis-cli DEL "online-testing:lab4:questions:test:$testId`:v1" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Redis is unavailable.' }

    $cold = Invoke-WebRequest $path -SkipHttpErrorCheck
    $hot = Invoke-WebRequest $path -SkipHttpErrorCheck
    Assert-Response $cold 200 'MISS'
    Assert-Response $hot 200 'HIT'

    $question = Invoke-WebRequest $path -Method Post -ContentType 'application/json' -Body (@{text='First version';order=1;points=1} | ConvertTo-Json) -SkipHttpErrorCheck
    Assert-Response $question 201
    $questionId = ($question.Content | ConvertFrom-Json).id
    $afterCreate = Invoke-WebRequest $path -SkipHttpErrorCheck
    Assert-Response $afterCreate 200 'MISS'
    if (-not $afterCreate.Content.Contains('First version')) { throw 'New question was not visible.' }

    $updated = Invoke-WebRequest "$BaseUrl/api/questions/$questionId" -Method Put -ContentType 'application/json' -Body (@{text='Second version';order=1;points=1} | ConvertTo-Json) -SkipHttpErrorCheck
    Assert-Response $updated 200
    $afterUpdate = Invoke-WebRequest $path -SkipHttpErrorCheck
    Assert-Response $afterUpdate 200 'MISS'
    if (-not $afterUpdate.Content.Contains('Second version')) { throw 'Updated question was not visible.' }

    & docker compose @composeArgs stop redis | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop Redis.' }
    $redisStopped = $true
    $fallback = Invoke-WebRequest $path -SkipHttpErrorCheck -TimeoutSec 15
    Assert-Response $fallback 200 'BYPASS'
    & docker compose @composeArgs start redis | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restore Redis.' }
    $redisStopped = $false

    $deleted = Invoke-WebRequest "$BaseUrl/api/tests/$testId" -Method Delete -SkipHttpErrorCheck
    Assert-Response $deleted 204
    $testId = $null
    $afterDelete = Invoke-WebRequest $path -SkipHttpErrorCheck
    Assert-Response $afterDelete 404 'MISS'
    Write-Host 'PASS student 2: MISS, HIT, question invalidation, test deletion, Redis fallback.'
}
finally {
    if ($redisStopped) { & docker compose @composeArgs start redis | Out-Null }
    if ($testId) { Invoke-WebRequest "$BaseUrl/api/tests/$testId" -Method Delete -SkipHttpErrorCheck | Out-Null }
}
