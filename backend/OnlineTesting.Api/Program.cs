
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

app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "OnlineTesting.Api",
    instanceId
}));

app.MapControllers();

app.Run();
