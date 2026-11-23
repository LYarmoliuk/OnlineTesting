param(
    [ValidateSet('single','legacy','bucket')][string]$Strategy = 'bucket',
    [ValidateRange(10,10000)][int]$Count = 300,
    [ValidateRange(0,100)][int]$HotPercent = 90,
    [long]$AttemptBase = 7000000,
    [string]$EventType = 'lab7-seed',
    [string]$BaseUrl = 'http://localhost:8081',
    [string]$OutputDirectory = 'docs/lab7-results'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $url = "$BaseUrl/api/lab7/events"
    $before = Invoke-RestMethod "$url/distribution?strategy=$Strategy"
    $times = [Collections.Generic.List[double]]::new()
    $writes = @{'shard-a'=0; 'shard-b'=0}
    for ($i=0; $i -lt $Count; $i++) {
        $student = if (($i % 100) -lt $HotPercent) { 'hot-student' } else { "student-$($i % 40)" }
        $body = @{studentId=$student;attemptId=($AttemptBase+$i);eventType=$EventType;payload="Lab7 seed $i";strategy=$Strategy} | ConvertTo-Json -Compress
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest $url -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
        $timer.Stop()
        if ($response.StatusCode -ne 201) { throw "Insert $i returned HTTP $($response.StatusCode)" }
        $shard = [string]$response.Headers['X-Shard-Node']
        if (-not $writes.ContainsKey($shard)) { throw "Unexpected shard $shard" }
        $writes[$shard]++
        $times.Add($timer.Elapsed.TotalMilliseconds)
    }
    $after = Invoke-RestMethod "$url/distribution?strategy=$Strategy"
    $sorted = @($times | Sort-Object)
    $rows = foreach ($shard in @('shard-a','shard-b')) {
        $old = [long](@($before.counts | Where-Object shard -eq $shard)[0].count)
        $now = [long](@($after.counts | Where-Object shard -eq $shard)[0].count)
        $delta = $now - $old
        if ($delta -ne $writes[$shard]) { throw "DB count disagrees with writes on $shard" }
        [pscustomobject]@{
            shard=$shard; records=$delta; dataPct=[math]::Round(100*$delta/$Count,2)
            writeOperations=$writes[$shard]; writePct=[math]::Round(100*$writes[$shard]/$Count,2)
        }
    }
    $result = [pscustomobject]@{
        strategy=$Strategy; count=$Count; hotPercent=$HotPercent; attemptBase=$AttemptBase; eventType=$EventType
        rows=@($rows)
        writeP95Ms=[math]::Round($sorted[[math]::Min($sorted.Count-1,[int][math]::Ceiling(0.95*$sorted.Count)-1)],2)
        writeP99Ms=[math]::Round($sorted[[math]::Min($sorted.Count-1,[int][math]::Ceiling(0.99*$sorted.Count)-1)],2)
    }
    $output = Join-Path $root $OutputDirectory
    New-Item -ItemType Directory -Force $output | Out-Null
    $result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $output "distribution-$Strategy.json") -Encoding utf8
    $result | ConvertTo-Json -Depth 6
} finally { Pop-Location }
