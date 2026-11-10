$ErrorActionPreference = 'Stop'
docker compose up -d db
if ($LASTEXITCODE -ne 0) { throw 'Primary did not start.' }
for ($i = 1; $i -le 30; $i++) {
    docker compose exec -T db pg_isready -U app -d online_testing *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 2
}
if ($LASTEXITCODE -ne 0) { throw 'Primary is not ready.' }
docker compose exec -T db bash /replication/primary-setup.sh
if ($LASTEXITCODE -ne 0) { throw 'Replication role setup failed.' }
docker compose up -d db_replica
if ($LASTEXITCODE -ne 0) { throw 'Replica did not start.' }
for ($i = 1; $i -le 30; $i++) {
    $ready = docker compose exec -T db_replica psql -U app -d online_testing -Atc 'SHOW in_hot_standby' 2>$null
    if ($LASTEXITCODE -eq 0 -and ($ready | Select-Object -Last 1) -eq 'on') { break }
    Start-Sleep -Seconds 2
}
if ($LASTEXITCODE -ne 0 -or ($ready | Select-Object -Last 1) -ne 'on') { throw 'Replica is not ready.' }
docker compose exec -T db psql -U app -d online_testing -c 'SELECT client_addr,state,sync_state FROM pg_stat_replication;'
docker compose exec -T db_replica psql -U app -d online_testing -c 'SELECT pg_is_in_recovery(),pg_last_wal_replay_lsn();'
