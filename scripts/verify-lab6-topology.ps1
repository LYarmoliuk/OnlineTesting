$ErrorActionPreference = 'Stop'
$primary = docker compose exec -T db psql -U app -d online_testing -Atc 'SELECT pg_is_in_recovery()'
$replica = docker compose exec -T db_replica psql -U app -d online_testing -Atc 'SELECT pg_is_in_recovery()'
if (($primary | Select-Object -Last 1) -ne 'f' -or ($replica | Select-Object -Last 1) -ne 't') { throw 'Primary/replica roles are incorrect.' }
$id = [guid]::NewGuid().ToString('N')
$sql = "CREATE TABLE IF NOT EXISTS lab6_replication_probe(id text PRIMARY KEY); INSERT INTO lab6_replication_probe(id) VALUES ('$id');"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app -d online_testing -c $sql | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Primary write failed.' }
$found = $false
for($i=0;$i -lt 20;$i++) {
    $value = docker compose exec -T db_replica psql -U app -d online_testing -Atc "SELECT id FROM lab6_replication_probe WHERE id='$id'" 2>$null
    if (($value | Select-Object -Last 1) -eq $id) { $found = $true; break }
    Start-Sleep -Milliseconds 500
}
docker compose exec -T db psql -U app -d online_testing -c "DELETE FROM lab6_replication_probe WHERE id='$id'" | Out-Null
if (-not $found) { throw 'WAL replication did not deliver the probe.' }
$write = docker compose exec -T db_replica psql -U app -d online_testing -c "INSERT INTO lab6_replication_probe(id) VALUES ('must-fail')" 2>&1
if ($LASTEXITCODE -eq 0) { throw 'Replica unexpectedly accepted a write.' }
Write-Host 'PASS: WAL replication and replica read-only mode.'
