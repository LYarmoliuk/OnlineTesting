
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using OnlineTesting.Api.Data;
using OnlineTesting.Api.Models;

namespace OnlineTesting.Api.Controllers;

public sealed class SaveStudentAnswerDto
{
    public int QuestionId { get; set; }
    public int SelectedOptionId { get; set; }
}

public sealed class StudentOptionDto
{
    public int Id { get; set; }
    public string Text { get; set; } = string.Empty;
}

public sealed class StudentQuestionDto
{
    public int Id { get; set; }
    public string Text { get; set; } = string.Empty;
    public int Order { get; set; }
    public int Points { get; set; }
    public int? SelectedOptionId { get; set; }
    public List<StudentOptionDto> Options { get; set; } = [];
}

public sealed class StudentAttemptResponseDto
{
    public int AttemptId { get; set; }
    public int TestId { get; set; }
    public string TestTitle { get; set; } = string.Empty;
    public Guid AccessToken { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public int? Score { get; set; }
    public List<StudentQuestionDto> Questions { get; set; } = [];
}

public sealed class AttemptResultDto
{
    public int AttemptId { get; set; }
    public string TestTitle { get; set; } = string.Empty;
    public int Score { get; set; }
    public int MaxScore { get; set; }
    public int AnsweredQuestions { get; set; }
    public int TotalQuestions { get; set; }
    public DateTime? CompletedAt { get; set; }
}

[ApiController]
[Route("api")]
public sealed class AttemptsController(AppDbContext dbContext)
    : ControllerBase
{
    private const string TokenHeader = "X-Attempt-Token";

    [HttpPost("tests/{testId:int}/attempts")]
    public async Task<ActionResult<StudentAttemptResponseDto>> StartAttempt(
        int testId,
        CancellationToken cancellationToken)
    {
        var test = await dbContext.Tests
            .Include(t => t.Questions)
                .ThenInclude(q => q.AnswerOptions)
            .FirstOrDefaultAsync(t => t.Id == testId, cancellationToken);

        if (test is null)
            return NotFound("Тест не знайдено.");

        if (!test.IsPublished)
            return Conflict("Тест ще не опубліковано.");

        if (test.Questions.Count == 0)
            return Conflict("У тесті немає запитань.");

        var invalidQuestion = test.Questions.Any(q =>
            q.AnswerOptions.Count < 2 ||
            q.AnswerOptions.Count(o => o.IsCorrect) != 1);

        if (invalidQuestion)
            return Conflict(
                "Кожне запитання має містити щонайменше два варіанти " +
                "та рівно одну правильну відповідь.");

        var attempt = new TestAttempt
        {
            TestId = test.Id,
            AccessToken = Guid.NewGuid(),
            StartedAt = DateTime.UtcNow,
            Status = TestAttemptStatus.InProgress
        };

        dbContext.TestAttempts.Add(attempt);
        await dbContext.SaveChangesAsync(cancellationToken);

        var response = new StudentAttemptResponseDto
        {
            AttemptId = attempt.Id,
            TestId = test.Id,
            TestTitle = test.Title,
            AccessToken = attempt.AccessToken,
            Status = attempt.Status.ToString(),
            StartedAt = attempt.StartedAt,
            Questions = test.Questions
                .OrderBy(q => q.Order)
                .Select(q => new StudentQuestionDto
                {
                    Id = q.Id,
                    Text = q.Text,
                    Order = q.Order,
                    Points = q.Points,
                    Options = q.AnswerOptions
                        .OrderBy(o => o.Id)
                        .Select(o => new StudentOptionDto
                        {
                            Id = o.Id,
                            Text = o.Text
                        })
                        .ToList()
                })
                .ToList()
        };

        return CreatedAtAction(
            nameof(GetAttempt),
            new { attemptId = attempt.Id },
            response);
    }

    [HttpGet("attempts/{attemptId:int}")]
    public async Task<ActionResult<StudentAttemptResponseDto>> GetAttempt(
        int attemptId,
        [FromHeader(Name = TokenHeader)] Guid accessToken,
        CancellationToken cancellationToken)
    {
        var attempt = await dbContext.TestAttempts
            .AsNoTracking()
            .Include(a => a.Test)
                .ThenInclude(t => t.Questions)
                    .ThenInclude(q => q.AnswerOptions)
            .Include(a => a.Answers)
            .FirstOrDefaultAsync(
                a => a.Id == attemptId && a.AccessToken == accessToken,
                cancellationToken);

        if (attempt is null)
            return NotFound("Спробу не знайдено.");

        var selectedOptions = attempt.Answers
            .ToDictionary(a => a.QuestionId, a => a.SelectedOptionId);

        var response = new StudentAttemptResponseDto
        {
            AttemptId = attempt.Id,
            TestId = attempt.TestId,
            TestTitle = attempt.Test.Title,
            Status = attempt.Status.ToString(),
            StartedAt = attempt.StartedAt,
            CompletedAt = attempt.CompletedAt,
            Score = attempt.Status == TestAttemptStatus.Completed
                ? attempt.Score
                : null,
            Questions = attempt.Test.Questions
                .OrderBy(q => q.Order)
                .Select(q => new StudentQuestionDto
                {
                    Id = q.Id,
                    Text = q.Text,
                    Order = q.Order,
                    Points = q.Points,
                    SelectedOptionId = selectedOptions.GetValueOrDefault(q.Id),
                    Options = q.AnswerOptions
                        .OrderBy(o => o.Id)
                        .Select(o => new StudentOptionDto
                        {
                            Id = o.Id,
                            Text = o.Text
                        })
                        .ToList()
                })
                .ToList()
        };

        return Ok(response);
    }

    [HttpPut("attempts/{attemptId:int}/answers")]
    public async Task<IActionResult> SaveAnswer(
        int attemptId,
        [FromHeader(Name = TokenHeader)] Guid accessToken,
        SaveStudentAnswerDto dto,
        CancellationToken cancellationToken)
    {
        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        var attempt = await LockAttemptAsync(attemptId, accessToken, cancellationToken);

        if (attempt is null)
            return NotFound("Спробу не знайдено.");

        if (attempt.Status != TestAttemptStatus.InProgress)
            return Conflict("Завершену спробу змінювати не можна.");

        var questionExists = await dbContext.Questions.AnyAsync(
            q => q.Id == dto.QuestionId && q.TestId == attempt.TestId,
            cancellationToken);

        if (!questionExists)
            return BadRequest("Запитання не належить цьому тесту.");

        var optionExists = await dbContext.AnswerOptions.AnyAsync(
            o => o.Id == dto.SelectedOptionId &&
                 o.QuestionId == dto.QuestionId,
            cancellationToken);

        if (!optionExists)
            return BadRequest(
                "Вибраний варіант не належить цьому запитанню.");

        var answer = await dbContext.StudentAnswers.FirstOrDefaultAsync(
            a => a.TestAttemptId == attempt.Id && a.QuestionId == dto.QuestionId,
            cancellationToken);

        if (answer is null)
        {
            answer = new StudentAnswer
            {
                TestAttemptId = attempt.Id,
                QuestionId = dto.QuestionId,
                SelectedOptionId = dto.SelectedOptionId,
                AnsweredAt = DateTime.UtcNow
            };

            dbContext.StudentAnswers.Add(answer);
        }
        else
        {
            answer.SelectedOptionId = dto.SelectedOptionId;
            answer.AnsweredAt = DateTime.UtcNow;
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return NoContent();
    }

    [HttpPost("attempts/{attemptId:int}/submit")]
    public async Task<ActionResult<AttemptResultDto>> SubmitAttempt(
        int attemptId,
        [FromHeader(Name = TokenHeader)] Guid accessToken,
        CancellationToken cancellationToken)
    {
        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        var lockedAttempt = await LockAttemptAsync(attemptId, accessToken, cancellationToken);

        if (lockedAttempt is null)
            return NotFound("Спробу не знайдено.");

        var attempt = await dbContext.TestAttempts
            .Include(a => a.Test)
                .ThenInclude(t => t.Questions)
            .Include(a => a.Answers)
                .ThenInclude(a => a.Question)
            .Include(a => a.Answers)
                .ThenInclude(a => a.SelectedOption)
            .FirstOrDefaultAsync(
                a => a.Id == attemptId && a.AccessToken == accessToken,
                cancellationToken);

        // Повторне надсилання не змінює вже збережений результат.
        if (attempt!.Status != TestAttemptStatus.Completed)
        {
            attempt.Score = attempt.Answers
                .Where(a => a.SelectedOption.IsCorrect)
                .Sum(a => a.Question.Points);

            attempt.CompletedAt = DateTime.UtcNow;
            attempt.Status = TestAttemptStatus.Completed;

            await dbContext.SaveChangesAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return Ok(BuildResult(attempt));
    }

    [HttpGet("attempts/{attemptId:int}/result")]
    public async Task<ActionResult<AttemptResultDto>> GetResult(
        int attemptId,
        [FromHeader(Name = TokenHeader)] Guid accessToken,
        CancellationToken cancellationToken)
    {
        var attempt = await dbContext.TestAttempts
            .AsNoTracking()
            .Include(a => a.Test)
                .ThenInclude(t => t.Questions)
            .Include(a => a.Answers)
            .FirstOrDefaultAsync(
                a => a.Id == attemptId && a.AccessToken == accessToken,
                cancellationToken);

        if (attempt is null)
            return NotFound("Спробу не знайдено.");

        if (attempt.Status != TestAttemptStatus.Completed)
            return Conflict("Спочатку потрібно завершити тест.");

        return Ok(BuildResult(attempt));
    }

    private static AttemptResultDto BuildResult(TestAttempt attempt)
    {
        return new AttemptResultDto
        {
            AttemptId = attempt.Id,
            TestTitle = attempt.Test.Title,
            Score = attempt.Score ?? 0,
            MaxScore = attempt.Test.Questions.Sum(q => q.Points),
            AnsweredQuestions = attempt.Answers.Count,
            TotalQuestions = attempt.Test.Questions.Count,
            CompletedAt = attempt.CompletedAt
        };
    }

    // The database row lock serializes answer saves and submission across all API instances.
    private async Task<TestAttempt?> LockAttemptAsync(
        int attemptId,
        Guid accessToken,
        CancellationToken cancellationToken) =>
        (await dbContext.TestAttempts
            .FromSqlInterpolated($"SELECT * FROM \"TestAttempts\" WHERE \"Id\" = {attemptId} AND \"AccessToken\" = {accessToken} FOR UPDATE")
            .AsNoTracking()
            .ToListAsync(cancellationToken)).SingleOrDefault();
}
