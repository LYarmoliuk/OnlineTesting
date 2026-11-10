param([string]$BaseUrl='http://localhost:8081')
$ErrorActionPreference = 'Stop'
$url = "$BaseUrl/api/tests"
try {
    docker compose stop db_replica | Out-Null
    $fallback = Invoke-WebRequest $url -Headers @{'X-Lab5-Cache-Bypass'='1'} -TimeoutSec 15
    if ($fallback.StatusCode -ne 200 -or $fallback.Headers['X-DB-Node'] -ne 'primary') { throw 'Replica fallback failed.' }
} finally { docker compose start db_replica | Out-Null }
for($i=0;$i -lt 20;$i++) {
    try { $r=Invoke-WebRequest $url -Headers @{'X-Lab5-Cache-Bypass'='1'} -TimeoutSec 5; if ($r.Headers['X-DB-Node'] -eq 'replica') { break } } catch { }
    Start-Sleep -Seconds 2
}
if ($r.Headers['X-DB-Node'] -ne 'replica') { throw 'Replica did not recover.' }
try {
    docker compose stop db | Out-Null
    $read=Invoke-WebRequest $url -Headers @{'X-Lab5-Cache-Bypass'='1'} -TimeoutSec 15
    if ($read.StatusCode -ne 200 -or $read.Headers['X-DB-Node'] -ne 'replica') { throw 'Replica read failed without primary.' }
    $write=Invoke-WebRequest $url -Method Post -ContentType 'application/json' -Body '{"title":"must-not-write","description":"lab6"}' -SkipHttpErrorCheck -TimeoutSec 15
    if ($write.StatusCode -lt 500) { throw 'Write succeeded without primary.' }
} finally { docker compose start db | Out-Null }
Write-Host 'PASS: replica fallback; read-only degradation when primary is down.'
