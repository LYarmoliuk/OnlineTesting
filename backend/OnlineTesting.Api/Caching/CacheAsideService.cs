using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;

namespace OnlineTesting.Api.Caching;

public sealed record CacheReadResult<T>(T Value, string Status);

public sealed class CacheAsideService(
    IDistributedCache cache,
    ILogger<CacheAsideService> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<CacheReadResult<T>> ReadAsync<T>(
        string key,
        TimeSpan ttl,
        Func<CancellationToken, Task<T>> loadFromDatabase,
        CancellationToken cancellationToken)
    {
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

        var fresh = await loadFromDatabase(cancellationToken);
        if (cacheAvailable)
        {
            try
            {
                await cache.SetStringAsync(
                    key,
                    JsonSerializer.Serialize(fresh, JsonOptions),
                    new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl },
                    cancellationToken);
                return new CacheReadResult<T>(fresh, "MISS");
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogWarning(exception, "Redis write failed for {CacheKey}; using PostgreSQL", key);
            }
        }

        return new CacheReadResult<T>(fresh, "BYPASS");
    }
}
