using Microsoft.EntityFrameworkCore;

namespace OnlineTesting.Api.Data;

// Only eventual-consistency queries should use this service. All writes and
// security/attempt reads continue to use the primary AppDbContext.
public sealed class ReplicaReadService(
    AppDbContext primary,
    IConfiguration configuration,
    ILogger<ReplicaReadService> logger)
{
    public async Task<(T Value, string Node)> ReadAsync<T>(
        Func<AppDbContext, CancellationToken, Task<T>> query,
        bool primaryOnly,
        CancellationToken cancellationToken)
    {
        var connection = configuration.GetConnectionString("ReplicaConnection");
        if (!primaryOnly && !string.IsNullOrWhiteSpace(connection))
        {
            try
            {
                var options = new DbContextOptionsBuilder<AppDbContext>()
                    .UseNpgsql(connection).Options;
                await using var replica = new AppDbContext(options);
                return (await query(replica, cancellationToken), "replica");
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Replica unavailable; falling back to primary");
            }
        }
        return (await query(primary, cancellationToken), "primary");
    }
}
