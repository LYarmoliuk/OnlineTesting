using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using StackExchange.Redis;

namespace OnlineTesting.Api.Caching;

public sealed record CacheReadResult<T>(T Value, string Status);

public sealed class CacheAsideService(
    IDistributedCache cache,
    IConnectionMultiplexer redis,
    ILogger<CacheAsideService> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static TimeSpan WithJitter(TimeSpan baseTtl, TimeSpan jitter)
    {
        var minimum = Math.Max(1L, (long)(baseTtl.TotalMilliseconds - jitter.TotalMilliseconds));
        var maximum = Math.Max(minimum, (long)(baseTtl.TotalMilliseconds + jitter.TotalMilliseconds));
        return TimeSpan.FromMilliseconds(Random.Shared.NextInt64(minimum, maximum + 1));
    }

    public async Task<CacheReadResult<T>> ReadAsync<T>(
        string key,
        TimeSpan ttl,
        Func<CancellationToken, Task<T>> loadFromDatabase,
        CancellationToken cancellationToken,
        bool bypassCache = false)
    {
        if (bypassCache)
            return new CacheReadResult<T>(await loadFromDatabase(cancellationToken), "BYPASS");

        var cacheAvailable = true;
        try
        {
            var json = await cache.GetStringAsync(key, cancellationToken);
            if (json is not null)
            {
                var value = JsonSerializer.Deserialize<T>(json, JsonOptions);
                if (value is not null)
                    return new CacheReadResult<T>(value, "HIT");
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            cacheAvailable = false;
            logger.LogWarning(exception, "Redis read failed for {CacheKey}; using PostgreSQL", key);
        }

        var database = redis.GetDatabase();
        var lockKey = $"{key}:refresh-lock";
        var lockToken = Guid.NewGuid().ToString("N");
        var lockAcquired = false;
        async Task ReleaseLockAsync()
        {
            if (!lockAcquired) return;
            try
            {
                await database.ScriptEvaluateAsync(
                    "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end",
                    [lockKey], [lockToken]);
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Redis lock release failed for {CacheKey}; lock will expire by TTL", key);
            }
        }
        try
        {
            lockAcquired = await database.StringSetAsync(lockKey, lockToken, TimeSpan.FromSeconds(15), When.NotExists);
            if (!lockAcquired)
            {
                for (var attempt = 0; attempt < 40; attempt++)
                {
                    await Task.Delay(TimeSpan.FromMilliseconds(50), cancellationToken);
                    var refreshed = await cache.GetStringAsync(key, cancellationToken);
                    if (refreshed is not null)
                    {
                        var value = JsonSerializer.Deserialize<T>(refreshed, JsonOptions);
                        if (value is not null) return new CacheReadResult<T>(value, "COALESCED");
                    }
                }
                lockAcquired = await database.StringSetAsync(lockKey, lockToken, TimeSpan.FromSeconds(15), When.NotExists);
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Redis coalescing lock failed for {CacheKey}; continuing without lock", key);
            lockAcquired = false;
        }

        // Another worker may have populated the cache just before this request acquired
        // the lock. Recheck under the lock so that this race does not trigger another DB read.
        if (lockAcquired && cacheAvailable)
        {
            try
            {
                var refreshed = await cache.GetStringAsync(key, cancellationToken);
                if (refreshed is not null)
                {
                    var value = JsonSerializer.Deserialize<T>(refreshed, JsonOptions);
                    if (value is not null)
                    {
                        await ReleaseLockAsync();
                        return new CacheReadResult<T>(value, "COALESCED");
                    }
                }
            }
            catch (OperationCanceledException)
            {
                await ReleaseLockAsync();
                throw;
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                cacheAvailable = false;
                logger.LogWarning(exception, "Redis cache recheck failed for {CacheKey}; loading PostgreSQL", key);
                await ReleaseLockAsync();
            }
        }

        T fresh;
        try { fresh = await loadFromDatabase(cancellationToken); }
        catch { await ReleaseLockAsync(); throw; }
        if (cacheAvailable)
        {
            try
            {
                await cache.SetStringAsync(
                    key,
                    JsonSerializer.Serialize(fresh, JsonOptions),
                    new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
                    cancellationToken);
                await ReleaseLockAsync();
                return new CacheReadResult<T>(fresh, lockAcquired ? "MISS" : "UNCOALESCED");
            }
            catch (OperationCanceledException)
            {
                await ReleaseLockAsync();
                throw;
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogWarning(exception, "Redis write failed for {CacheKey}; using PostgreSQL", key);
            }
        }

        await ReleaseLockAsync();
        return new CacheReadResult<T>(fresh, "BYPASS");
    }
}
