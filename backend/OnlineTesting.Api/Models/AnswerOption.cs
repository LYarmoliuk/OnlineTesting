
using System.ComponentModel.DataAnnotations;

namespace OnlineTesting.Api.Models;

public class AnswerOption
{
    public int Id { get; set; }

    public int QuestionId { get; set; }

    [Required]
    [MaxLength(1000)]
    public string Text { get; set; } = string.Empty;

    public bool IsCorrect { get; set; }

    public Question Question { get; set; } = null!;
}
