param(
    [ValidateRange(2,300)][int]$StageSeconds=15,
    [string]$BaseUrl='http://host.docker.internal:8081',
    [switch]$Smoke,
    [switch]$HotOnly,
    [switch]$ReadExtendedOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$resultFolder=if($Smoke){'docs/lab7-results/smoke'}else{'docs/lab7-results'}
$results=Join-Path $root $resultFolder
New-Item -ItemType Directory -Force $results|Out-Null
$localUrl=$BaseUrl.Replace('host.docker.internal','localhost')
$count=if($Smoke){20}else{300}
$levels=if($Smoke){@(1)}elseif($ReadExtendedOnly){@(100,200)}else{@(5,20,50,100,200)}
$duration=if($Smoke){2}else{$StageSeconds}
$metadataPath=Join-Path $results $(if($Smoke){'smoke-metadata.json'}else{'run-metadata.json'})
if(-not $HotOnly -and -not $ReadExtendedOnly) {
    $seedType='lab7-seed-'+[guid]::NewGuid().ToString('N')
    @{seedType=$seedType;count=$count;stageSeconds=$duration}|ConvertTo-Json|Set-Content $metadataPath -Encoding utf8
    foreach($strategy in @('single','legacy','bucket')) {
        & (Join-Path $root 'scripts/lab7-generate.ps1') -Strategy $strategy -Count $count -BaseUrl $localUrl -EventType $seedType -OutputDirectory $resultFolder | Out-Null
    }
    & (Join-Path $root 'scripts/lab7-reshard-model.ps1') -Output (Join-Path $resultFolder 'resharding.json') | Out-Null
} else {
    $seedType=(Get-Content $metadataPath -Raw|ConvertFrom-Json).seedType
}
$rows=[Collections.Generic.List[object]]::new()
if($HotOnly -or $ReadExtendedOnly) {
    foreach($old in @(Get-Content (Join-Path $results 'summary.json') -Raw|ConvertFrom-Json)) { $rows.Add($old) }
}

function Invoke-Lab7K6([string]$label,[string]$mode,[string]$strategy,[int]$vus,[int]$seconds,[bool]$sampleStats) {
    $name="$label-$vus"
    $statsPath=Join-Path $results "$name-docker-stats.txt"
    $job=$null
    if($sampleStats) {
        if(Test-Path $statsPath) { Remove-Item -LiteralPath $statsPath }
        $job=Start-Job -ArgumentList $statsPath -ScriptBlock {
            param($path)
            while($true) {
                $stamp=[DateTime]::UtcNow.ToString('o')
                docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' onlinetesting-db-1 onlinetesting-db_shard_b-1 |
                    ForEach-Object { Add-Content $path "$stamp|$_" }
                Start-Sleep -Seconds 1
            }
        }
    }
    try {
        $output=& docker run --rm --cpus 1 --memory 512m -v "${PSScriptRoot}:/src:ro" -v "${results}:/results" grafana/k6:1.5.0 run --vus $vus --duration "${seconds}s" --summary-trend-stats 'avg,p(95),p(99)' --summary-export "/results/$name.json" -e "BASE_URL=$BaseUrl" -e "LAB7_MODE=$mode" -e "LAB7_STRATEGY=$strategy" -e "LAB7_SEED_COUNT=$count" -e "LAB7_SEED_TYPE=$seedType" /src/lab7.js 2>&1
        if($LASTEXITCODE -ne 0) { throw "k6 $name failed: $($output|Select-Object -Last 15|Out-String)" }
    } finally {
        if($job) { Stop-Job $job; Receive-Job $job|Out-Null; Remove-Job $job }
    }
    $metrics=(Get-Content (Join-Path $results "$name.json") -Raw|ConvertFrom-Json).metrics
    $row=[pscustomobject]@{
        mode=$label; strategy=$strategy; vus=$vus; seconds=$seconds
        requests=[int]$metrics.http_reqs.count
        rps=[math]::Round($metrics.http_reqs.rate,2)
        p95Ms=[math]::Round($metrics.http_req_duration.'p(95)',2)
        p99Ms=[math]::Round($metrics.http_req_duration.'p(99)',2)
        errorPct=[math]::Round(100*$metrics.http_req_failed.value,4)
        failedChecks=[int]$metrics.checks.fails
    }
    if($Smoke -and ($row.failedChecks -gt 0 -or $row.errorPct -gt 0)) { throw "Failed requests in ${name}: $($row|ConvertTo-Json -Compress)" }
    if($row.failedChecks -gt 0 -or $row.errorPct -gt 0) {
        Write-Warning "${name}: $($row.failedChecks) failed checks, $($row.errorPct)% HTTP errors."
    } else {
        Write-Host "PASS $name RPS=$($row.rps) p99=$($row.p99Ms)ms"
    }
    return $row
}

if(-not $HotOnly) {
    foreach($vus in $levels) {
        $rows.Add((Invoke-Lab7K6 'single-local' 'read-local' 'single' $vus $duration $false))
        $rows.Add((Invoke-Lab7K6 'sharded-local' 'read-local' 'bucket' $vus $duration $false))
        $rows.Add((Invoke-Lab7K6 'fanout' 'read-fanout' 'bucket' $vus $duration $false))
    }
}
if(-not $ReadExtendedOnly) { foreach($strategy in @('legacy','bucket')) {
    $hotLevels=if($Smoke){@(1)}elseif($HotOnly){@(5)}else{@(5,50)}
    foreach($vus in $hotLevels) {
        $before=Invoke-RestMethod "$localUrl/api/lab7/events/distribution?strategy=$strategy"
        $rows.Add((Invoke-Lab7K6 "hot-$strategy" 'write-hot' $strategy $vus $duration $true))
        $after=Invoke-RestMethod "$localUrl/api/lab7/events/distribution?strategy=$strategy"
        $distribution=foreach($shard in @('shard-a','shard-b')) {
            $old=[long](@($before.counts|Where-Object shard -eq $shard)[0].count)
            $now=[long](@($after.counts|Where-Object shard -eq $shard)[0].count)
            [pscustomobject]@{shard=$shard;writes=($now-$old)}
        }
        $distribution|ConvertTo-Json|Set-Content (Join-Path $results "hot-$strategy-$vus-distribution.json") -Encoding utf8
    }
} }
$summary=if($Smoke){'smoke-summary.json'}else{'summary.json'}
$rows.ToArray()|ConvertTo-Json -Depth 6|Set-Content (Join-Path $results $summary) -Encoding utf8
if(-not $Smoke) { & (Join-Path $PSScriptRoot 'render-lab7.ps1') }
$rows|Format-Table -AutoSize
