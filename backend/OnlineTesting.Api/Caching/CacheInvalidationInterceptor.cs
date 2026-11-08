using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Caching.Distributed;
using OnlineTesting.Api.Models;

namespace OnlineTesting.Api.Caching;

public sealed class CacheInvalidationInterceptor(
    IDistributedCache cache,
    ILogger<CacheInvalidationInterceptor> logger) : SaveChangesInterceptor
{
    private readonly HashSet<string> pendingKeys = [];

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        CollectKeys(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    public override async ValueTask<int> SavedChangesAsync(
        SaveChangesCompletedEventData eventData,
        int result,
        CancellationToken cancellationToken = default)
    {
        foreach (var key in pendingKeys)
        {
            try
            {
                await cache.RemoveAsync(key, CancellationToken.None);
                logger.LogInformation("Invalidated cache key {CacheKey}", key);
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Redis invalidation failed for {CacheKey}", key);
            }
        }
        pendingKeys.Clear();
        return await base.SavedChangesAsync(eventData, result, cancellationToken);
    }

    public override Task SaveChangesFailedAsync(
        DbContextErrorEventData eventData,
        CancellationToken cancellationToken = default)
    {
        pendingKeys.Clear();
        return base.SaveChangesFailedAsync(eventData, cancellationToken);
    }

    private void CollectKeys(DbContext? context)
    {
        pendingKeys.Clear();
        if (context is null) return;

        foreach (var entry in context.ChangeTracker.Entries<Test>())
        {
            if (entry.State is not (EntityState.Added or EntityState.Modified or EntityState.Deleted))
                continue;

            pendingKeys.Add(CacheKeys.TestsList);
            if (entry.State == EntityState.Deleted)
                pendingKeys.Add(CacheKeys.QuestionsForTest(entry.Entity.Id));
        }

        foreach (var entry in context.ChangeTracker.Entries<Question>())
        {
            if (entry.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
                pendingKeys.Add(CacheKeys.QuestionsForTest(entry.Entity.TestId));
        }
    }
}
