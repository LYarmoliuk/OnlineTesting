
using Microsoft.EntityFrameworkCore;
using Npgsql;
using OnlineTesting.Api.Caching;
using OnlineTesting.Api.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddCors(options =>
{
    options.AddPolicy("VueFrontend", policy =>
    {
        policy
            .WithOrigins("http://localhost:5173")
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration["Cache:RedisConnection"]
        ?? "redis:6379,abortConnect=false,connectTimeout=1000,syncTimeout=1000";
    options.InstanceName = "online-testing:lab4:";
});
builder.Services.AddScoped<CacheAsideService>();
builder.Services.AddScoped<CacheInvalidationInterceptor>();
builder.Services.AddScoped<ReplicaReadService>();
builder.Services.AddDbContext<AppDbContext>((services, options) =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection"))
        .AddInterceptors(services.GetRequiredService<CacheInvalidationInterceptor>()));

var app = builder.Build();

if (args.Contains("--migrate", StringComparer.Ordinal))
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    return;
}

var instanceId = Environment.GetEnvironmentVariable("INSTANCE_ID") ?? Environment.MachineName;
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Instance-ID"] = instanceId;
    try { await next(context); }
    catch (Exception ex) when (
        ex is NpgsqlException or DbUpdateException or TimeoutException ||
        ex is InvalidOperationException { InnerException: NpgsqlException or DbUpdateException or TimeoutException })
    {
        if (context.Response.HasStarted) throw;
        context.Response.Clear();
        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        await context.Response.WriteAsJsonAsync(new { error = "Primary database unavailable", mode = "read-only" });
    }
});

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("VueFrontend");

app.MapGet("/health", async (AppDbContext db, CancellationToken cancellationToken) =>
{
    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    timeout.CancelAfter(TimeSpan.FromSeconds(2));

    bool databaseReady;
    try
    {
        databaseReady = await db.Database.CanConnectAsync(timeout.Token);
    }
    catch (Exception)
    {
        databaseReady = false;
    }

    var report = new
    {
        status = databaseReady ? "healthy" : "unavailable",
        service = "OnlineTesting.Api",
        instanceId,
        database = databaseReady ? "connected" : "unavailable"
    };

    return databaseReady
        ? Results.Ok(report)
        : Results.Json(report, statusCode: StatusCodes.Status503ServiceUnavailable);
});

app.MapControllers();

app.Run();
