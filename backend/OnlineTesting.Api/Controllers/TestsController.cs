
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using OnlineTesting.Api.Caching;
using OnlineTesting.Api.Data;
using OnlineTesting.Api.DTOs;
using OnlineTesting.Api.Models;

namespace OnlineTesting.Api.Controllers;

[ApiController]
[Route("api/tests")]
public sealed class TestsController(AppDbContext dbContext, CacheAsideService cache, ReplicaReadService reads, IWebHostEnvironment environment)
    : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IEnumerable<TestResponseDto>>> GetTests(
        CancellationToken cancellationToken)
    {
        var node = "cache";
        var primaryOnly = Request.Headers["X-Lab6-Primary-Only"] == "1";
        var result = await cache.ReadAsync(
            CacheKeys.TestsList,
            TimeSpan.FromSeconds(30),
            async token =>
            {
                var read = await reads.ReadAsync((db, ct) => db.Tests
                .AsNoTracking()
                .OrderByDescending(test => test.CreatedAt)
                .Select(test => new TestResponseDto
                {
                    Id = test.Id,
                    Title = test.Title,
                    Description = test.Description,
                    IsPublished = test.IsPublished,
                    CreatedAt = test.CreatedAt
                })
                .ToListAsync(ct), primaryOnly, token);
                node = read.Node;
                return read.Value;
            },
            cancellationToken,
            (environment.IsDevelopment() && Request.Headers["X-Lab5-Cache-Bypass"] == "1") || primaryOnly);

        Response.Headers["X-Cache"] = result.Status;
        Response.Headers["X-DB-Node"] = node;
        return Ok(result.Value);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<TestResponseDto>> GetTest(
        int id,
        CancellationToken cancellationToken)
    {
        Response.Headers["X-DB-Node"] = "primary";
        var test = await dbContext.Tests
            .AsNoTracking()
            .Where(test => test.Id == id)
            .Select(test => new TestResponseDto
            {
                Id = test.Id,
                Title = test.Title,
                Description = test.Description,
                IsPublished = test.IsPublished,
                CreatedAt = test.CreatedAt
            })
            .FirstOrDefaultAsync(cancellationToken);

        if (test is null)
        {
            return NotFound();
        }

        return Ok(test);
    }

    [HttpPost]
    public async Task<ActionResult<TestResponseDto>> CreateTest(
        CreateTestDto dto,
        CancellationToken cancellationToken)
    {
        var test = new Test
        {
            Title = dto.Title.Trim(),
            Description = dto.Description.Trim(),
            IsPublished = false,
            CreatedAt = DateTime.UtcNow
        };

        if (string.IsNullOrWhiteSpace(test.Title))
        {
            return BadRequest("Назва тесту не може бути порожньою.");
        }

        dbContext.Tests.Add(test);
        await dbContext.SaveChangesAsync(cancellationToken);

        var response = new TestResponseDto
        {
            Id = test.Id,
            Title = test.Title,
            Description = test.Description,
            IsPublished = test.IsPublished,
            CreatedAt = test.CreatedAt
        };

        return CreatedAtAction(
            nameof(GetTest),
            new { id = test.Id },
            response);
    }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<TestResponseDto>> UpdateTest(
        int id,
        UpdateTestDto dto,
        CancellationToken cancellationToken)
    {
        var test = await dbContext.Tests
            .FirstOrDefaultAsync(
                test => test.Id == id,
                cancellationToken);

        if (test is null)
        {
            return NotFound();
        }

        var title = dto.Title.Trim();

        if (string.IsNullOrWhiteSpace(title))
        {
            return BadRequest("Назва тесту не може бути порожньою.");
        }

        test.Title = title;
        test.Description = dto.Description.Trim();
        test.IsPublished = dto.IsPublished;

        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new TestResponseDto
        {
            Id = test.Id,
            Title = test.Title,
            Description = test.Description,
            IsPublished = test.IsPublished,
            CreatedAt = test.CreatedAt
        });
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> DeleteTest(
        int id,
        CancellationToken cancellationToken)
    {
        var test = await dbContext.Tests
            .FirstOrDefaultAsync(
                test => test.Id == id,
                cancellationToken);

        if (test is null)
        {
            return NotFound();
        }

        dbContext.Tests.Remove(test);
        await dbContext.SaveChangesAsync(cancellationToken);

        return NoContent();
    }
}
