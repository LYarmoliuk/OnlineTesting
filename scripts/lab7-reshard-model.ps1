param([ValidateRange(100,100000)][int]$Keys=10000,
      [string]$Output='docs/lab7-results/resharding.json')
$ErrorActionPreference='Stop'
function Hash32([string]$value) {
    $bytes=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($value))
    [BitConverter]::ToUInt32([byte[]]$bytes[3..0],0)
}
function Owner([int]$bucket,[string[]]$nodes) {
    $best=''; [uint64]$score=0
    foreach($node in $nodes) {
        $hash=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("${bucket}:$node"))
        [uint64]$candidate=[BitConverter]::ToUInt64([byte[]]$hash[7..0],0)
        if($candidate -gt $score -or ($candidate -eq $score -and [string]::CompareOrdinal($node,$best) -lt 0)) {
            $best=$node; $score=$candidate
        }
    }
    $best
}
$two=@('shard-a','shard-b'); $three=@('shard-a','shard-b','shard-c')
$bucketMoved=0
for($bucket=0;$bucket -lt 64;$bucket++) {
    if((Owner $bucket $two) -ne (Owner $bucket $three)) { $bucketMoved++ }
}
$naiveMoved=0; $virtualMoved=0
for($i=0;$i -lt $Keys;$i++) {
    $hash=Hash32 "student-$($i%131):$i"
    if(($hash%2) -ne ($hash%3)) { $naiveMoved++ }
    $bucket=[int]($hash%64)
    if((Owner $bucket $two) -ne (Owner $bucket $three)) { $virtualMoved++ }
}
$result=[pscustomobject]@{
    keys=$Keys; virtualBuckets=64; addedShard='shard-c'; movedBuckets=$bucketMoved
    naiveMoved=$naiveMoved; naiveMovedPct=[math]::Round(100*$naiveMoved/$Keys,2)
    virtualMoved=$virtualMoved; virtualMovedPct=[math]::Round(100*$virtualMoved/$Keys,2)
    theoreticalNewShardSharePct=[math]::Round(100/3,2)
}
$root=Split-Path -Parent $PSScriptRoot
$path=Join-Path $root $Output
New-Item -ItemType Directory -Force (Split-Path $path -Parent)|Out-Null
$result|ConvertTo-Json|Set-Content $path -Encoding utf8
$result|ConvertTo-Json
