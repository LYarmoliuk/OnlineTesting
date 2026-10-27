
using Microsoft.EntityFrameworkCore;
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

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection")));

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
    await next(context);
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
