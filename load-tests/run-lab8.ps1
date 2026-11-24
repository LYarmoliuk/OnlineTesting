param([string]$BaseUrl='http://host.docker.internal:8081', [string]$Image='grafana/k6:1.5.0', [ValidateRange(10,600)][int]$StageSeconds=30, [switch]$Smoke)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'docs/lab8-results'
New-Item -ItemType Directory -Force $out|Out-Null
$frontendId=(& docker compose ps -q frontend | Select-Object -First 1).Trim()
if(-not $frontendId){throw 'Start the Docker Compose frontend before running the Lab 8 load test.'}
$network=(& docker inspect $frontendId --format '{{range $name, $config := .NetworkSettings.Networks}}{{println $name}}{{end}}' | Select-Object -First 1).Trim()
if(-not $network){throw 'Could not find the Compose network attached to frontend.'}
$k6BaseUrl=if($BaseUrl -eq 'http://host.docker.internal:8081'){'http://frontend'}else{$BaseUrl}
$duration=if($Smoke){'3s'}else{"${StageSeconds}s"}
$vus=if($Smoke){10}else{500}
$rows=[Collections.Generic.List[object]]::new()
foreach($mode in @('unprotected','protected','penetration','avalanche-sync','avalanche-jitter')) {
    $reset=$BaseUrl.Replace('host.docker.internal','localhost')+'/api/lab8/reset'
    Invoke-WebRequest $reset -Method Delete -SkipHttpErrorCheck|Out-Null
    $key="lab8-$mode-$([guid]::NewGuid().ToString('N'))"
    $json="/results/$mode.json"
    $args=@('run','--vus',$vus,'--duration',$duration,'--summary-trend-stats','avg,p(95),p(99)','--summary-export',$json,'-e',"BASE_URL=$k6BaseUrl",'-e',"MODE=$mode",'-e',"KEY_ID=$key",'/src/lab8.js')
    & docker run --network $network --rm --cpus 1 --memory 512m -v "${PSScriptRoot}:/src:ro" -v "${out}:/results" $Image @args | Out-Host
    if($LASTEXITCODE -ne 0){throw "k6 failed for $mode"}
    $m=(Get-Content (Join-Path $out "$mode.json") -Raw|ConvertFrom-Json).metrics
    $loads=Invoke-RestMethod ($BaseUrl.Replace('host.docker.internal','localhost')+'/api/lab8/metrics')
    $rows.Add([pscustomobject]@{mode=$mode;vus=$vus;seconds=if($Smoke){3}else{$StageSeconds};requests=[long]$m.http_reqs.count;rps=[math]::Round($m.http_reqs.rate,2);p95Ms=[math]::Round($m.http_req_duration.'p(95)',2);p99Ms=[math]::Round($m.http_req_duration.'p(99)',2);errorPct=[math]::Round(100*$m.http_req_failed.value,4);failedChecks=[int]$m.checks.fails;resourceDbLoads=$loads.resourceDatabaseLoads;entityDbLoads=$loads.entityDatabaseLoads;avalancheDbLoads=$loads.avalancheDatabaseLoads})
}
$rows.ToArray()|ConvertTo-Json -Depth 5|Set-Content (Join-Path $out 'summary.json') -Encoding utf8
& (Join-Path $PSScriptRoot 'render-lab8.ps1')
$rows|Format-Table -AutoSize
