param([string]$BaseUrl='http://localhost:8081')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
$created=[Collections.Generic.List[object]]::new()
function Assert([bool]$ok,[string]$message) { if(-not $ok) { throw $message } }
try {
    $services=@(docker compose ps --services --status running)
    foreach($required in @('db','db_shard_b','db_replica','redis','api_a','api_b','api_c','frontend')) {
        Assert ($services -contains $required) "Service $required is not running."
    }
    $base="$BaseUrl/api/lab7/events"
    $single=Invoke-RestMethod "$base/route?studentId=hot-student&attemptId=1&strategy=single"
    Assert ($single.shard -eq 'shard-a') 'Single topology must use Shard A.'
    $legacy1=Invoke-RestMethod "$base/route?studentId=hot-student&attemptId=1&strategy=legacy"
    $legacy2=Invoke-RestMethod "$base/route?studentId=hot-student&attemptId=99&strategy=legacy"
    Assert ($legacy1.shard -eq $legacy2.shard) 'Legacy key must be sticky for a student.'
    $targets=@{}
    for($id=1;$id -le 100 -and $targets.Count -lt 2;$id++) {
        $route=Invoke-RestMethod "$base/route?studentId=hot-student&attemptId=$id&strategy=bucket"
        if(-not $targets.ContainsKey($route.shard)) { $targets[$route.shard]=$id }
    }
    Assert ($targets.Count -eq 2) 'Composite key did not reach both shards.'
    $marker='lab7probe_'+[guid]::NewGuid().ToString('N')
    foreach($shard in @('shard-a','shard-b')) {
        $attempt=[long]$targets[$shard]
        $body=@{studentId='hot-student';attemptId=$attempt;eventType=$marker;payload='create';strategy='bucket'}|ConvertTo-Json -Compress
        $write=Invoke-WebRequest $base -Method Post -ContentType 'application/json' -Body $body
        Assert ($write.StatusCode -eq 201 -and $write.Headers['X-Shard-Node'] -eq $shard) "POST was not routed to $shard."
        $event=$write.Content|ConvertFrom-Json
        $created.Add($event)
        $container=if($shard -eq 'shard-a'){'db'}else{'db_shard_b'}
        $count=docker compose exec -T $container psql -U app -d online_testing -Atc "SELECT count(*) FROM lab7_events WHERE event_id='$($event.eventId)'"
        Assert ($LASTEXITCODE -eq 0 -and ($count|Select-Object -Last 1) -eq '1') "Physical row is missing on $shard."
        $url="$base/hot-student/$attempt/$($event.eventId)?strategy=bucket"
        $read=Invoke-RestMethod $url
        Assert ($read.eventId -eq $event.eventId -and $read.shard -eq $shard) 'GET returned the wrong event.'
        $update=Invoke-WebRequest $url -Method Put -ContentType 'application/json' -Body (@{eventType=$marker;payload='updated'}|ConvertTo-Json)
        Assert ($update.StatusCode -eq 204 -and (Invoke-RestMethod $url).payload -eq 'updated') 'PUT failed.'
        $local=Invoke-RestMethod "$base/local?studentId=hot-student&attemptId=$attempt&strategy=bucket&term=$marker"
        Assert ($local.shards.Count -eq 1 -and @($local.items|Where-Object eventId -eq $event.eventId).Count -eq 1) 'Local query failed.'
    }
    $search=Invoke-RestMethod "$base/search?strategy=bucket&term=$marker"
    Assert ($search.shards.Count -eq 2 -and $search.items.Count -eq 2) 'Fan-out did not gather both shards.'
    $distribution=Invoke-RestMethod "$base/distribution?strategy=bucket"
    Assert ($distribution.counts.Count -eq 2) 'Distribution did not inspect two physical shards.'
    Write-Host 'PASS Lab 7: deterministic routing, two physical shards, CRUD, local query, fan-out and distribution.'
} finally {
    foreach($event in $created) {
        try {
            $url="$BaseUrl/api/lab7/events/$($event.studentId)/$($event.attemptId)/$($event.eventId)?strategy=$($event.strategy)"
            Invoke-WebRequest $url -Method Delete -SkipHttpErrorCheck|Out-Null
        } catch { Write-Warning "Could not remove probe event $($event.eventId): $_" }
    }
    Pop-Location
}
