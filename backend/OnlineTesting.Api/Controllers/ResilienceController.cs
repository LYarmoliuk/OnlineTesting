using System.Diagnostics;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using OnlineTesting.Api.Caching;
using OnlineTesting.Api.Data;
using StackExchange.Redis;

namespace OnlineTesting.Api.Controllers;

[ApiController]
[Route("api/lab8")]
public sealed class ResilienceController(
    CacheAsideService cache,
    IDistributedCache distributedCache,
    IConnectionMultiplexer redis,
    AppDbContext dbContext,
    ILogger<ResilienceController> logger) : ControllerBase
{
    private static readonly TimeSpan BaseTtl = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan Jitter = TimeSpan.FromSeconds(10);

    [HttpGet("resource/{id}")]
    public async Task<IActionResult> GetResource(string id, [FromQuery] bool protectedMode = true,
        [FromQuery] int delayMs = 200, CancellationToken ct = default)
    {
        var key = $"lab8:resource:{id}";
        var ttl = CacheAsideService.WithJitter(BaseTtl, Jitter);
        async Task<object> Load(CancellationToken token)
        {
            await RecordLoadAsync("lab8:db-loads");
            var test = await dbContext.Tests.AsNoTracking()
                .OrderByDescending(item => item.CreatedAt)
                .Select(item => new { item.Id, item.Title, item.Description, item.IsPublished, item.CreatedAt })
                .FirstOrDefaultAsync(token);
            await Task.Delay(Math.Clamp(delayMs, 0, 5000), token);
            return new
            {
                id = test?.Id ?? 0,
                key = id,
                title = test?.Title,
                description = test?.Description,
                isPublished = test?.IsPublished,
                createdAt = test?.CreatedAt
            };
        }

        var sw = Stopwatch.StartNew();
        CacheReadResult<object> result;
        if (protectedMode)
            result = await cache.ReadAsync<object>(key, ttl, Load, ct);
        else
        {
            var cached = await distributedCache.GetStringAsync(key, ct);
            if (cached is not null)
            {
                result = new(JsonSerializer.Deserialize<JsonElement>(cached), "HIT");
            }
            else
            {
                var value = await Load(ct);
                await distributedCache.SetStringAsync(key, JsonSerializer.Serialize(value),
                    new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl }, ct);
                result = new(value, "MISS");
            }
        }
        sw.Stop();
        Response.Headers["X-Cache"] = result.Status;
        Response.Headers["X-Cache-TTL-Seconds"] = ttl.TotalSeconds.ToString("0.##");
        Response.Headers["X-Lab8-Latency-Ms"] = sw.Elapsed.TotalMilliseconds.ToString("0.##");
        return Ok(result.Value);
    }

    [HttpGet("entity/{id:int}")]
    public async Task<IActionResult> GetEntity(int id, CancellationToken ct)
    {
        var cacheKey = $"lab8:entity:{id}";
        var cached = await distributedCache.GetStringAsync(cacheKey, ct);
        if (cached == "missing")
        {
            Response.Headers["X-Cache"] = "NEGATIVE-HIT";
            return NotFound();
        }

        await RecordLoadAsync("lab8:entity-db-loads");
        var entity = await dbContext.Tests.AsNoTracking()
            .Where(test => test.Id == id)
            .Select(test => new { test.Id, test.Title, test.Description, test.IsPublished, test.CreatedAt })
            .FirstOrDefaultAsync(ct);
        if (entity is null)
        {
            await distributedCache.SetStringAsync(cacheKey, "missing",
                new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(15) }, ct);
            Response.Headers["X-Cache"] = "NEGATIVE-MISS";
            return NotFound();
        }

        await distributedCache.SetStringAsync(cacheKey, JsonSerializer.Serialize(entity),
            new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = CacheAsideService.WithJitter(BaseTtl, Jitter) }, ct);
        Response.Headers["X-Cache"] = "MISS";
        return Ok(entity);
    }

    [HttpGet("avalanche")]
    public async Task<IActionResult> Avalanche([FromQuery] bool jitter = false,
        [FromQuery] int ttlSeconds = 5, CancellationToken ct = default)
    {
        // A group of related keys exposes synchronized expiry. In jitter mode each key
        // receives an independent expiration window around the same base TTL.
        const int keyCount = 20;
        var misses = 0;
        for (var i = 0; i < keyCount; i++)
        {
            var key = $"lab8:avalanche:{i}";
            var cached = await distributedCache.GetStringAsync(key, ct);
            if (cached is not null) continue;
            misses++;
            await RecordLoadAsync("lab8:avalanche-db-loads");
            _ = await dbContext.Tests.AsNoTracking()
                .OrderByDescending(test => test.CreatedAt)
                .Select(test => test.Id)
                .FirstOrDefaultAsync(ct);
            await Task.Delay(25, ct);
            var baseTtl = TimeSpan.FromSeconds(Math.Clamp(ttlSeconds, 2, 60));
            var halfTtlMs = (long)(baseTtl.TotalMilliseconds / 2);
            var ttl = jitter
                ? baseTtl + TimeSpan.FromMilliseconds(Random.Shared.NextInt64(-halfTtlMs, halfTtlMs + 1))
                : baseTtl;
            await distributedCache.SetStringAsync(key, "ok",
                new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = ttl }, ct);
        }
        Response.Headers["X-Cache-Misses"] = misses.ToString();
        return Ok(new { keyCount, misses, jitter, ttlSeconds = Math.Clamp(ttlSeconds, 2, 60), message = "PostgreSQL-backed cache avalanche demonstration group" });
    }

    [HttpDelete("reset")]
    public async Task<IActionResult> Reset(CancellationToken ct)
    {
        var db = redis.GetDatabase();
        await db.KeyDeleteAsync("lab8:db-loads");
        await db.KeyDeleteAsync("lab8:entity-db-loads");
        await db.KeyDeleteAsync("lab8:avalanche-db-loads");
        foreach (var key in redis.GetServer(redis.GetEndPoints()[0]).Keys(pattern: "online-testing:lab4:lab8:*"))
            await db.KeyDeleteAsync(key);
        foreach (var key in redis.GetServer(redis.GetEndPoints()[0]).Keys(pattern: "lab8:resource:*:refresh-lock"))
            await db.KeyDeleteAsync(key);
        return NoContent();
    }

    [HttpGet("metrics")]
    public async Task<IActionResult> Metrics()
    {
        var db = redis.GetDatabase();
        var loads = (long?)await db.StringGetAsync("lab8:db-loads") ?? 0;
        var entityLoads = (long?)await db.StringGetAsync("lab8:entity-db-loads") ?? 0;
        var avalancheLoads = (long?)await db.StringGetAsync("lab8:avalanche-db-loads") ?? 0;
        return Ok(new { resourceDatabaseLoads = loads, entityDatabaseLoads = entityLoads, avalancheDatabaseLoads = avalancheLoads });
    }

    private async Task RecordLoadAsync(string counterKey)
    {
        try { await redis.GetDatabase().StringIncrementAsync(counterKey); }
        catch (Exception exception) { logger.LogWarning(exception, "Lab 8 load metric unavailable for {CounterKey}", counterKey); }
    }
}
