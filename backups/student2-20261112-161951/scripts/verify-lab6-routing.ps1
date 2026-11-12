param([string]$BaseUrl='http://localhost:8081')
$ErrorActionPreference = 'Stop'
$base="$BaseUrl/api/tests"
$replica=Invoke-WebRequest $base -Headers @{'X-Lab5-Cache-Bypass'='1'}
if ($replica.Headers['X-DB-Node'] -ne 'replica') { throw 'Catalog did not use replica.' }
$primary=Invoke-WebRequest $base -Headers @{'X-Lab6-Primary-Only'='1'}
if ($primary.Headers['X-DB-Node'] -ne 'primary') { throw 'Explicit primary routing failed.' }
$test=Invoke-RestMethod $base -Method Post -ContentType 'application/json' -Body (@{title='Lab6-'+[guid]::NewGuid().ToString('N');description='Temporary consistency probe'}|ConvertTo-Json)
try {
    $read=Invoke-WebRequest "$base/$($test.id)"
    if ($read.StatusCode -ne 200 -or $read.Headers['X-DB-Node'] -ne 'primary') { throw 'Read-after-write failed.' }
} finally { Invoke-RestMethod "$base/$($test.id)" -Method Delete | Out-Null }
Write-Host 'PASS: eventual catalog on replica, strict object read on primary.'
