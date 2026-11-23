using System.ComponentModel.DataAnnotations;
using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using NpgsqlTypes;
using OnlineTesting.Api.Sharding;

namespace OnlineTesting.Api.Controllers;

public sealed class Lab7EventInput
{
    [Required, StringLength(64, MinimumLength = 1)] public string StudentId { get; set; } = "";
    [Range(1, long.MaxValue)] public long AttemptId { get; set; }
    [Required, StringLength(64, MinimumLength = 1)] public string EventType { get; set; } = "";
    [StringLength(512)] public string Payload { get; set; } = "";
    public string Strategy { get; set; } = "bucket";
    public Guid? EventId { get; set; }
}

public sealed class Lab7EventUpdate
{
    [Required, StringLength(64, MinimumLength = 1)] public string EventType { get; set; } = "";
    [StringLength(512)] public string Payload { get; set; } = "";
}

public sealed record Lab7Event(
    string Strategy, string StudentId, long AttemptId, Guid EventId,
    string EventType, string Payload, DateTime CreatedAt, string Shard);

[ApiController]
[Route("api/lab7/events")]
public sealed class Lab7EventsController(IConfiguration configuration) : ControllerBase
{
    private static bool ValidStrategy(string strategy) => strategy is "single" or "legacy" or "bucket";

    private string ConnectionFor(string shard) =>
        configuration.GetConnectionString(shard == "shard-a" ? "ShardAConnection" : "ShardBConnection")
        ?? throw new InvalidOperationException($"Missing connection string for {shard}.");

    private static Lab7Event ReadEvent(NpgsqlDataReader r, string shard) =>
        new(r.GetString(0), r.GetString(1), r.GetInt64(2), r.GetGuid(3),
            r.GetString(4), r.GetString(5), r.GetDateTime(6), shard);

    private static void KeyParameters(NpgsqlCommand command, string strategy, string studentId, long attemptId)
    {
        command.Parameters.AddWithValue("strategy", strategy);
        command.Parameters.AddWithValue("sid", studentId);
        command.Parameters.AddWithValue("aid", attemptId);
    }

    [HttpGet("route")]
    public IActionResult Route([FromQuery] string studentId, [FromQuery] long attemptId,
        [FromQuery] string strategy = "bucket")
    {
        if (string.IsNullOrWhiteSpace(studentId) || attemptId <= 0 || !ValidStrategy(strategy))
            return BadRequest("studentId, positive attemptId and strategy=single|legacy|bucket are required.");
        var (shard, bucket) = ShardRouter.Route(studentId, attemptId, strategy);
        return Ok(new { shard, bucket = bucket < 0 ? (int?)null : bucket, strategy });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] Lab7EventInput input, CancellationToken ct)
    {
        if (!ValidStrategy(input.Strategy) || string.IsNullOrWhiteSpace(input.StudentId) ||
            string.IsNullOrWhiteSpace(input.EventType)) return BadRequest("Invalid shard strategy or event fields.");
        var (shard, bucket) = ShardRouter.Route(input.StudentId, input.AttemptId, input.Strategy);
        var id = input.EventId ?? Guid.NewGuid();
        await using var connection = new NpgsqlConnection(ConnectionFor(shard));
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand("""
            INSERT INTO lab7_events (strategy,student_id,attempt_id,event_id,event_type,payload)
            VALUES (@strategy,@sid,@aid,@id,@type,@payload)
            RETURNING created_at
            """, connection);
        KeyParameters(command, input.Strategy, input.StudentId, input.AttemptId);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("type", input.EventType);
        command.Parameters.AddWithValue("payload", input.Payload);
        var createdAt = (DateTime)(await command.ExecuteScalarAsync(ct))!;
        Response.Headers["X-Shard-Node"] = shard;
        Response.Headers["X-Virtual-Bucket"] = bucket.ToString();
        return Created($"/api/lab7/events/{Uri.EscapeDataString(input.StudentId)}/{input.AttemptId}/{id}?strategy={input.Strategy}",
            new Lab7Event(input.Strategy, input.StudentId, input.AttemptId, id,
                input.EventType, input.Payload, createdAt, shard));
    }

    [HttpGet("{studentId}/{attemptId:long}/{eventId:guid}")]
    public async Task<IActionResult> Get(string studentId, long attemptId, Guid eventId,
        [FromQuery] string strategy = "bucket", CancellationToken ct = default)
    {
        if (!ValidStrategy(strategy)) return BadRequest("Invalid strategy.");
        var (shard, _) = ShardRouter.Route(studentId, attemptId, strategy);
        Response.Headers["X-Shard-Node"] = shard;
        await using var connection = new NpgsqlConnection(ConnectionFor(shard));
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand("""
            SELECT strategy,student_id,attempt_id,event_id,event_type,payload,created_at
            FROM lab7_events WHERE strategy=@strategy AND student_id=@sid
              AND attempt_id=@aid AND event_id=@id
            """, connection);
        KeyParameters(command, strategy, studentId, attemptId);
        command.Parameters.AddWithValue("id", eventId);
        await using var reader = await command.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct) ? Ok(ReadEvent(reader, shard)) : NotFound();
    }

    [HttpPut("{studentId}/{attemptId:long}/{eventId:guid}")]
    public async Task<IActionResult> Update(string studentId, long attemptId, Guid eventId,
        [FromBody] Lab7EventUpdate input, [FromQuery] string strategy = "bucket", CancellationToken ct = default)
    {
        if (!ValidStrategy(strategy) || string.IsNullOrWhiteSpace(input.EventType)) return BadRequest("Invalid strategy or event type.");
        var (shard, _) = ShardRouter.Route(studentId, attemptId, strategy);
        Response.Headers["X-Shard-Node"] = shard;
        await using var connection = new NpgsqlConnection(ConnectionFor(shard));
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand("""
            UPDATE lab7_events SET event_type=@type,payload=@payload
            WHERE strategy=@strategy AND student_id=@sid AND attempt_id=@aid AND event_id=@id
            """, connection);
        KeyParameters(command, strategy, studentId, attemptId);
        command.Parameters.AddWithValue("id", eventId);
        command.Parameters.AddWithValue("type", input.EventType);
        command.Parameters.AddWithValue("payload", input.Payload);
        return await command.ExecuteNonQueryAsync(ct) == 1 ? NoContent() : NotFound();
    }

    [HttpDelete("{studentId}/{attemptId:long}/{eventId:guid}")]
    public async Task<IActionResult> Delete(string studentId, long attemptId, Guid eventId,
        [FromQuery] string strategy = "bucket", CancellationToken ct = default)
    {
        if (!ValidStrategy(strategy)) return BadRequest("Invalid strategy.");
        var (shard, _) = ShardRouter.Route(studentId, attemptId, strategy);
        Response.Headers["X-Shard-Node"] = shard;
        await using var connection = new NpgsqlConnection(ConnectionFor(shard));
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand("""
            DELETE FROM lab7_events WHERE strategy=@strategy AND student_id=@sid
              AND attempt_id=@aid AND event_id=@id
            """, connection);
        KeyParameters(command, strategy, studentId, attemptId);
        command.Parameters.AddWithValue("id", eventId);
        return await command.ExecuteNonQueryAsync(ct) == 1 ? NoContent() : NotFound();
    }

    private async Task<List<Lab7Event>> QueryShard(string shard, string strategy,
        string? studentId, long? attemptId, string term, int limit, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(ConnectionFor(shard));
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand("""
            SELECT strategy,student_id,attempt_id,event_id,event_type,payload,created_at
            FROM lab7_events WHERE strategy=@strategy
              AND (@sid IS NULL OR student_id=@sid)
              AND (@aid IS NULL OR attempt_id=@aid)
              AND (@term = '' OR event_type = @term)
            ORDER BY created_at DESC LIMIT @limit
            """, connection);
        command.Parameters.AddWithValue("strategy", strategy);
        command.Parameters.Add("sid", NpgsqlDbType.Varchar).Value = (object?)studentId ?? DBNull.Value;
        command.Parameters.Add("aid", NpgsqlDbType.Bigint).Value = (object?)attemptId ?? DBNull.Value;
        command.Parameters.AddWithValue("term", term);
        command.Parameters.AddWithValue("limit", limit);
        var items = new List<Lab7Event>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) items.Add(ReadEvent(reader, shard));
        return items;
    }

    [HttpGet("local")]
    public async Task<IActionResult> Local([FromQuery] string studentId, [FromQuery] long attemptId,
        [FromQuery] string strategy = "bucket", [FromQuery] string term = "",
        [FromQuery] int limit = 100, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(studentId) || attemptId <= 0 || !ValidStrategy(strategy) || limit is < 1 or > 1000)
            return BadRequest("Invalid query parameters.");
        var (shard, _) = ShardRouter.Route(studentId, attemptId, strategy);
        var timer = Stopwatch.StartNew();
        var items = await QueryShard(shard, strategy, studentId, attemptId, term, limit, ct);
        Response.Headers["X-Shard-Node"] = shard;
        return Ok(new { items, shards = new[] { shard }, elapsedMs = timer.Elapsed.TotalMilliseconds });
    }

    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string strategy = "bucket",
        [FromQuery] string term = "", [FromQuery] int limit = 100, CancellationToken ct = default)
    {
        if (!ValidStrategy(strategy) || limit is < 1 or > 1000) return BadRequest("Invalid query parameters.");
        var timer = Stopwatch.StartNew();
        var results = await Task.WhenAll(ShardRouter.CurrentShards.Select(
            shard => QueryShard(shard, strategy, null, null, term, limit, ct)));
        var items = results.SelectMany(x => x).OrderByDescending(x => x.CreatedAt).Take(limit).ToList();
        return Ok(new { items, shards = ShardRouter.CurrentShards, elapsedMs = timer.Elapsed.TotalMilliseconds });
    }

    [HttpGet("distribution")]
    public async Task<IActionResult> Distribution([FromQuery] string strategy = "bucket", CancellationToken ct = default)
    {
        if (!ValidStrategy(strategy)) return BadRequest("Invalid strategy.");
        var counts = await Task.WhenAll(ShardRouter.CurrentShards.Select(async shard =>
        {
            await using var connection = new NpgsqlConnection(ConnectionFor(shard));
            await connection.OpenAsync(ct);
            await using var command = new NpgsqlCommand("SELECT count(*) FROM lab7_events WHERE strategy=@strategy", connection);
            command.Parameters.AddWithValue("strategy", strategy);
            return new { shard, count = (long)(await command.ExecuteScalarAsync(ct))! };
        }));
        return Ok(new { strategy, counts, total = counts.Sum(x => x.count) });
    }
}
