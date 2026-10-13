
using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using OnlineTesting.Api.Data;
using OnlineTesting.Api.Models;

namespace OnlineTesting.Api.Controllers;

public sealed class CreateQuestionDto
{
    [Required]
    [StringLength(2000, MinimumLength = 1)]
    public string Text { get; set; } = string.Empty;

    [Range(0, int.MaxValue)]
    public int Order { get; set; }

    [Range(1, int.MaxValue)]
    public int Points { get; set; } = 1;
}

public sealed class CreateAnswerOptionDto
{
    [Required]
    [StringLength(1000, MinimumLength = 1)]
    public string Text { get; set; } = string.Empty;

    public bool IsCorrect { get; set; }
}

public sealed class UpdateQuestionDto
{
    [Required]
    [StringLength(2000, MinimumLength = 1)]
    public string Text { get; set; } = string.Empty;

    [Range(0, int.MaxValue)]
    public int Order { get; set; }

    [Range(1, int.MaxValue)]
    public int Points { get; set; } = 1;
}

public sealed class UpdateAnswerOptionDto
{
    [Required]
    [StringLength(1000, MinimumLength = 1)]
    public string Text { get; set; } = string.Empty;

    public bool IsCorrect { get; set; }
}

public sealed class QuestionResponseDto
{
    public int Id { get; set; }
    public int TestId { get; set; }
    public string Text { get; set; } = string.Empty;
    public int Order { get; set; }
    public int Points { get; set; }
}

public sealed class AnswerOptionResponseDto
{
    public int Id { get; set; }
    public int QuestionId { get; set; }
    public string Text { get; set; } = string.Empty;
    public bool IsCorrect { get; set; }
}

[ApiController]
[Route("api")]
public sealed class QuestionsController(AppDbContext dbContext)
    : ControllerBase
{
    [HttpGet("tests/{testId:int}/questions")]
    public async Task<ActionResult<IEnumerable<QuestionResponseDto>>> GetQuestions(
        int testId,
        CancellationToken cancellationToken)
    {
        var testExists = await dbContext.Tests
            .AnyAsync(test => test.Id == testId, cancellationToken);

        if (!testExists)
            return NotFound("Тест не знайдено.");

        var questions = await dbContext.Questions
            .AsNoTracking()
            .Where(question => question.TestId == testId)
            .OrderBy(question => question.Order)
            .Select(question => new QuestionResponseDto
            {
                Id = question.Id,
                TestId = question.TestId,
                Text = question.Text,
                Order = question.Order,
                Points = question.Points
            })
            .ToListAsync(cancellationToken);

        return Ok(questions);
    }

    [HttpPost("tests/{testId:int}/questions")]
    public async Task<ActionResult<QuestionResponseDto>> CreateQuestion(
        int testId,
        CreateQuestionDto dto,
        CancellationToken cancellationToken)
    {
        var testExists = await dbContext.Tests
            .AnyAsync(test => test.Id == testId, cancellationToken);

        if (!testExists)
            return NotFound("Тест не знайдено.");

        var text = dto.Text.Trim();

        if (string.IsNullOrWhiteSpace(text))
            return BadRequest("Текст запитання не може бути порожнім.");

        var question = new Question
        {
            TestId = testId,
            Text = text,
            Order = dto.Order,
            Points = dto.Points
        };

        dbContext.Questions.Add(question);
        await dbContext.SaveChangesAsync(cancellationToken);

        var response = new QuestionResponseDto
        {
            Id = question.Id,
            TestId = question.TestId,
            Text = question.Text,
            Order = question.Order,
            Points = question.Points
        };

        return Created(
            $"/api/questions/{question.Id}",
            response);
    }

    [HttpPut("questions/{id:int}")]
    public async Task<ActionResult<QuestionResponseDto>> UpdateQuestion(
        int id,
        UpdateQuestionDto dto,
        CancellationToken cancellationToken)
    {
        var question = await dbContext.Questions
            .FirstOrDefaultAsync(
                question => question.Id == id,
                cancellationToken);

        if (question is null)
            return NotFound("Запитання не знайдено.");

        var text = dto.Text.Trim();

        if (string.IsNullOrWhiteSpace(text))
            return BadRequest("Текст запитання не може бути порожнім.");

        question.Text = text;
        question.Order = dto.Order;
        question.Points = dto.Points;

        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new QuestionResponseDto
        {
            Id = question.Id,
            TestId = question.TestId,
            Text = question.Text,
            Order = question.Order,
            Points = question.Points
        });
    }

    [HttpPost("questions/{questionId:int}/options")]
    public async Task<ActionResult<AnswerOptionResponseDto>> CreateAnswerOption(
        int questionId,
        CreateAnswerOptionDto dto,
        CancellationToken cancellationToken)
    {
        var questionExists = await dbContext.Questions
            .AnyAsync(
                question => question.Id == questionId,
                cancellationToken);

        if (!questionExists)
            return NotFound("Запитання не знайдено.");

        var text = dto.Text.Trim();

        if (string.IsNullOrWhiteSpace(text))
            return BadRequest("Текст варіанта відповіді не може бути порожнім.");

        var option = new AnswerOption
        {
            QuestionId = questionId,
            Text = text,
            IsCorrect = dto.IsCorrect
        };

        dbContext.AnswerOptions.Add(option);
        await dbContext.SaveChangesAsync(cancellationToken);

        var response = new AnswerOptionResponseDto
        {
            Id = option.Id,
            QuestionId = option.QuestionId,
            Text = option.Text,
            IsCorrect = option.IsCorrect
        };

        return Created(
            $"/api/options/{option.Id}",
            response);
    }

    [HttpPut("options/{id:int}")]
    public async Task<ActionResult<AnswerOptionResponseDto>> UpdateAnswerOption(
        int id,
        UpdateAnswerOptionDto dto,
        CancellationToken cancellationToken)
    {
        var option = await dbContext.AnswerOptions
            .FirstOrDefaultAsync(
                option => option.Id == id,
                cancellationToken);

        if (option is null)
            return NotFound("Варіант відповіді не знайдено.");

        var text = dto.Text.Trim();

        if (string.IsNullOrWhiteSpace(text))
            return BadRequest("Текст варіанта відповіді не може бути порожнім.");

        option.Text = text;
        option.IsCorrect = dto.IsCorrect;

        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new AnswerOptionResponseDto
        {
            Id = option.Id,
            QuestionId = option.QuestionId,
            Text = option.Text,
            IsCorrect = option.IsCorrect
        });
    }

    [HttpDelete("options/{id:int}")]
    public async Task<IActionResult> DeleteAnswerOption(
        int id,
        CancellationToken cancellationToken)
    {
        var option = await dbContext.AnswerOptions
            .FirstOrDefaultAsync(
                option => option.Id == id,
                cancellationToken);

        if (option is null)
            return NotFound();

        dbContext.AnswerOptions.Remove(option);
        await dbContext.SaveChangesAsync(cancellationToken);

        return NoContent();
    }

    
    [HttpGet("questions/{id:int}")]
    public async Task<ActionResult<QuestionResponseDto>> GetQuestion(
        int id,
        CancellationToken cancellationToken)
    {
        var question = await dbContext.Questions
            .AsNoTracking()
            .Where(q => q.Id == id)
            .Select(q => new QuestionResponseDto
            {
                Id = q.Id,
                TestId = q.TestId,
                Text = q.Text,
                Order = q.Order,
                Points = q.Points
            })
            .FirstOrDefaultAsync(cancellationToken);

        return question is null ? NotFound() : Ok(question);
    }

    [HttpDelete("questions/{id:int}")]
    public async Task<IActionResult> DeleteQuestion(
        int id,
        CancellationToken cancellationToken)
    {
        var question = await dbContext.Questions
            .FirstOrDefaultAsync(q => q.Id == id, cancellationToken);

        if (question is null)
            return NotFound();

        dbContext.Questions.Remove(question);
        await dbContext.SaveChangesAsync(cancellationToken);

        return NoContent();
    }

    [HttpGet("questions/{questionId:int}/options")]
    public async Task<ActionResult<IEnumerable<AnswerOptionResponseDto>>>
        GetAnswerOptions(
            int questionId,
            CancellationToken cancellationToken)
    {
        var questionExists = await dbContext.Questions
            .AnyAsync(q => q.Id == questionId, cancellationToken);

        if (!questionExists)
            return NotFound("Запитання не знайдено.");

        var options = await dbContext.AnswerOptions
            .AsNoTracking()
            .Where(o => o.QuestionId == questionId)
            .Select(o => new AnswerOptionResponseDto
            {
                Id = o.Id,
                QuestionId = o.QuestionId,
                Text = o.Text,
                IsCorrect = o.IsCorrect
            })
            .ToListAsync(cancellationToken);

        return Ok(options);
    }

    [HttpGet("options/{id:int}")]
    public async Task<ActionResult<AnswerOptionResponseDto>> GetAnswerOption(
        int id,
        CancellationToken cancellationToken)
    {
        var option = await dbContext.AnswerOptions
            .AsNoTracking()
            .Where(o => o.Id == id)
            .Select(o => new AnswerOptionResponseDto
            {
                Id = o.Id,
                QuestionId = o.QuestionId,
                Text = o.Text,
                IsCorrect = o.IsCorrect
            })
            .FirstOrDefaultAsync(cancellationToken);

        return option is null ? NotFound() : Ok(option);
    }

}
