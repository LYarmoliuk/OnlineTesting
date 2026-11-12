param([string]$BaseUrl='http://localhost:8081')
$ErrorActionPreference='Stop'
$url="$BaseUrl/api/tests"
$test=$null
try {
    docker compose exec -T db_replica psql -U app -d online_testing -c 'SELECT pg_wal_replay_pause();' | Out-Null
    $test=Invoke-RestMethod $url -Method Post -ContentType 'application/json' -Body (@{title='Lab6-lag-'+[guid]::NewGuid().ToString('N');description='Temporary stale-read probe'}|ConvertTo-Json)
    $catalog=Invoke-RestMethod $url -Headers @{'X-Lab5-Cache-Bypass'='1'}
    if (@($catalog|Where-Object id -eq $test.id).Count -ne 0) { throw 'Expected stale replica read was not observed.' }
    $freshCatalog=Invoke-WebRequest $url -Headers @{'X-Lab6-Primary-Only'='1'}
    if ($freshCatalog.Headers['X-DB-Node'] -ne 'primary' -or
        @($freshCatalog.Content|ConvertFrom-Json|Where-Object id -eq $test.id).Count -ne 1) {
        throw 'Primary-only catalog did not contain the new test.'
    }
    $question=Invoke-RestMethod "$url/$($test.id)/questions" -Method Post -ContentType 'application/json' -Body '{"text":"Fresh question","order":1,"points":1}'
    $freshQuestions=Invoke-WebRequest "$url/$($test.id)/questions" -Headers @{'X-Lab6-Primary-Only'='1'}
    if ($freshQuestions.Headers['X-DB-Node'] -ne 'primary' -or
        @($freshQuestions.Content|ConvertFrom-Json|Where-Object id -eq $question.id).Count -ne 1) {
        throw 'Primary-only questions did not contain the new question.'
    }
    $strong=Invoke-WebRequest "$url/$($test.id)"
    if ($strong.StatusCode -ne 200 -or $strong.Headers['X-DB-Node'] -ne 'primary') { throw 'Read-after-write primary route failed.' }
    Write-Host "PASS: stale replica catalog; primary returned new test $($test.id)."
} finally {
    docker compose exec -T db_replica psql -U app -d online_testing -c 'SELECT pg_wal_replay_resume();' | Out-Null
    if ($test) { Invoke-RestMethod "$url/$($test.id)" -Method Delete | Out-Null }
}
