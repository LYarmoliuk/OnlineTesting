param([string]$OutFile = 'load-tests/results/student1/environment.json')

$ErrorActionPreference = 'Stop'
$docker = (& docker info --format '{{json .}}' | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Docker is unavailable.' }
$services = @(& docker compose ps --format json | ForEach-Object { $_ | ConvertFrom-Json })
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose is unavailable.' }
$connections = & docker compose exec -T db psql -U app -d online_testing -Atc 'SHOW max_connections'
if ($LASTEXITCODE -ne 0) { throw 'Cannot read PostgreSQL max_connections.' }
$result = [pscustomobject]@{
    capturedAt = (Get-Date).ToString('o')
    gitCommit = (& git rev-parse HEAD)
    dockerCpus = $docker.NCPU
    dockerMemoryBytes = $docker.MemTotal
    generatorLimit = '1 CPU / 512 MiB; separate k6 container on the same Docker host'
    sutCpuRamLimits = 'No per-service CPU/RAM limits in docker-compose.yml; shared Docker allocation'
    apiInstances = @($services | Where-Object { $_.Service -match '^api_[abc]$' -and $_.State -eq 'running' }).Count
    postgresMaxConnections = [int]($connections | Select-Object -Last 1)
    npgsqlConnectionPool = 'Maximum Pool Size=20 per API instance; three instances allow up to 60 pooled DB connections'
    redis = @($services | Where-Object { $_.Service -eq 'redis' } | Select-Object Service,State,Health)
    services = @($services | Select-Object Service,State,Health)
}
$parent = Split-Path -Parent $OutFile
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutFile -Encoding utf8
$result
