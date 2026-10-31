using Microsoft.AspNetCore.Mvc;

namespace OnlineTesting.Api.Controllers;

// A read-only, deterministic workload for the Lab 3 load-balancing experiment.
[ApiController]
[Route("api/benchmark")]
public sealed class BenchmarkController : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        var configured = Environment.GetEnvironmentVariable("LAB3_DELAY_MS");
        var delayMs = int.TryParse(configured, out var parsed)
            ? Math.Clamp(parsed, 0, 5000)
            : 0;

        if (delayMs > 0)
            await Task.Delay(delayMs, cancellationToken);

        return Ok(new
        {
            instanceId = Environment.GetEnvironmentVariable("INSTANCE_ID") ?? Environment.MachineName,
            delayMs
        });
    }
}
