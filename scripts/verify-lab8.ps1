param([string]$BaseUrl='http://localhost:8081')
$ErrorActionPreference='Stop'
$null=Invoke-RestMethod "$BaseUrl/api/lab8/reset" -Method Delete
$id='verify-'+[guid]::NewGuid().ToString('N')
$cold=Invoke-WebRequest "$BaseUrl/api/lab8/resource/$id`?protectedMode=true" -SkipHttpErrorCheck
if($cold.StatusCode -ne 200 -or $cold.Headers['X-Cache'] -ne 'MISS'){throw 'Protected resource cold read did not return MISS.'}
$hit=Invoke-WebRequest "$BaseUrl/api/lab8/resource/$id`?protectedMode=true" -SkipHttpErrorCheck
if($hit.StatusCode -ne 200 -or $hit.Headers['X-Cache'] -ne 'HIT'){throw 'Cached resource hit failed.'}
$negative1=Invoke-WebRequest "$BaseUrl/api/lab8/entity/9999999" -SkipHttpErrorCheck
$negative2=Invoke-WebRequest "$BaseUrl/api/lab8/entity/9999999" -SkipHttpErrorCheck
if($negative1.StatusCode -ne 404 -or $negative1.Headers['X-Cache'] -ne 'NEGATIVE-MISS' -or
   $negative2.StatusCode -ne 404 -or $negative2.Headers['X-Cache'] -ne 'NEGATIVE-HIT'){throw 'Negative caching did not work.'}
$ttlHeader=@($cold.Headers['X-Cache-TTL-Seconds']) | Select-Object -First 1
if([string]::IsNullOrWhiteSpace([string]$ttlHeader)){throw 'Protected resource did not return X-Cache-TTL-Seconds.'}
$ttl=0.0
$parsed=[double]::TryParse([string]$ttlHeader,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$ttl)
if(-not $parsed){throw "TTL header is not a valid number: $ttlHeader"}
if($ttl -lt 20 -or $ttl -gt 40){throw "TTL jitter outside expected 20-40 seconds: $ttl"}

# Concurrent cold reads should share one database load through the Redis lock.
$null=Invoke-RestMethod "$BaseUrl/api/lab8/reset" -Method Delete
$parallelId='coalesced-'+[guid]::NewGuid().ToString('N')
$before=[long](Invoke-RestMethod "$BaseUrl/api/lab8/metrics").resourceDatabaseLoads
$parallel=1..24 | ForEach-Object -Parallel {
    Invoke-WebRequest "$using:BaseUrl/api/lab8/resource/$using:parallelId`?protectedMode=true&delayMs=1000" -SkipHttpErrorCheck |
        Select-Object -ExpandProperty StatusCode
} -ThrottleLimit 24
if(@($parallel|Where-Object {$_ -ne 200}).Count -gt 0){throw 'One or more concurrent protected reads failed.'}
$after=[long](Invoke-RestMethod "$BaseUrl/api/lab8/metrics").resourceDatabaseLoads
if(($after-$before) -gt 2){throw "Request coalescing expected at most 2 source loads, observed $($after-$before)."}

# Synchronized expiration should reload the whole key group together.
$null=Invoke-RestMethod "$BaseUrl/api/lab8/reset" -Method Delete
$sync1=Invoke-RestMethod "$BaseUrl/api/lab8/avalanche?jitter=false&ttlSeconds=2"
$sync2=Invoke-RestMethod "$BaseUrl/api/lab8/avalanche?jitter=false&ttlSeconds=2"
Start-Sleep -Milliseconds 2300
$sync3=Invoke-RestMethod "$BaseUrl/api/lab8/avalanche?jitter=false&ttlSeconds=2"
if($sync1.misses -ne 20 -or $sync2.misses -ne 0 -or $sync3.misses -ne 20){throw 'Synchronized TTL expiration did not reload the full key group.'}

# With jitter, a request near the base expiration should see a partial wave.
$null=Invoke-RestMethod "$BaseUrl/api/lab8/reset" -Method Delete
$jitter1=Invoke-RestMethod "$BaseUrl/api/lab8/avalanche?jitter=true&ttlSeconds=4"
Start-Sleep -Milliseconds 4200
$jitter2=Invoke-RestMethod "$BaseUrl/api/lab8/avalanche?jitter=true&ttlSeconds=4"
if($jitter1.misses -ne 20 -or $jitter2.misses -lt 1 -or $jitter2.misses -ge 20){throw "Expected a partial expiration wave with jitter, observed $($jitter2.misses) misses."}

Write-Host 'PASS Lab 8: protected cache hit, TTL jitter, negative caching, concurrent request coalescing, synchronized avalanche and jittered expiration.'
