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
    & docker compose @composeArgs exec -T redis redis-cli DEL 'online-testing:lab4:tests:list:v1' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Redis is unavailable.' }

    $cold = Invoke-WebRequest "$BaseUrl/api/tests" -SkipHttpErrorCheck
    $hot = Invoke-WebRequest "$BaseUrl/api/tests" -SkipHttpErrorCheck
    Assert-Response $cold 200 'MISS'
    Assert-Response $hot 200 'HIT'

    $title = "Lab4 student1 $([guid]::NewGuid().ToString('N'))"
    $created = Invoke-WebRequest "$BaseUrl/api/tests" -Method Post -ContentType 'application/json' -Body (@{title=$title;description='cache verification'} | ConvertTo-Json) -SkipHttpErrorCheck
    Assert-Response $created 201
    $testId = ($created.Content | ConvertFrom-Json).id
    $afterCreate = Invoke-WebRequest "$BaseUrl/api/tests" -SkipHttpErrorCheck
    Assert-Response $afterCreate 200 'MISS'
    if (-not $afterCreate.Content.Contains($title)) { throw 'Created test was not visible.' }

    $updatedTitle = "$title updated"
    $updated = Invoke-WebRequest "$BaseUrl/api/tests/$testId" -Method Put -ContentType 'application/json' -Body (@{title=$updatedTitle;description='cache verification';isPublished=$false} | ConvertTo-Json) -SkipHttpErrorCheck
    Assert-Response $updated 200
    $afterUpdate = Invoke-WebRequest "$BaseUrl/api/tests" -SkipHttpErrorCheck
    Assert-Response $afterUpdate 200 'MISS'
    if (-not $afterUpdate.Content.Contains($updatedTitle)) { throw 'Updated title was not visible.' }

    $deleted = Invoke-WebRequest "$BaseUrl/api/tests/$testId" -Method Delete -SkipHttpErrorCheck
    Assert-Response $deleted 204
    $testId = $null
    $afterDelete = Invoke-WebRequest "$BaseUrl/api/tests" -SkipHttpErrorCheck
    Assert-Response $afterDelete 200 'MISS'
    if ($afterDelete.Content.Contains($title)) { throw 'Deleted test remained in the list.' }

    & docker compose @composeArgs stop redis | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop Redis.' }
    $redisStopped = $true
    $fallback = Invoke-WebRequest "$BaseUrl/api/tests" -SkipHttpErrorCheck -TimeoutSec 15
    Assert-Response $fallback 200 'BYPASS'
    Write-Host 'PASS student 1: MISS, HIT, POST/PUT/DELETE invalidation, Redis fallback.'
}
finally {
    if ($redisStopped) { & docker compose @composeArgs start redis | Out-Null }
    if ($testId) { Invoke-WebRequest "$BaseUrl/api/tests/$testId" -Method Delete -SkipHttpErrorCheck | Out-Null }
}
