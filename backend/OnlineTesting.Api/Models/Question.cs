
using System.ComponentModel.DataAnnotations;

namespace OnlineTesting.Api.Models;

public class Question
{
    public int Id { get; set; }

    public int TestId { get; set; }

    [Required]
    [MaxLength(2000)]
    public string Text { get; set; } = string.Empty;

    public int Order { get; set; }

    public int Points { get; set; } = 1;

    public Test Test { get; set; } = null!;

    public ICollection<AnswerOption> AnswerOptions { get; set; }
        = new List<AnswerOption>();
}
