namespace OnlineTesting.Api.Models;

public class StudentAnswer
{
    public int Id { get; set; }

    public int TestAttemptId { get; set; }

    public int QuestionId { get; set; }

    public int SelectedOptionId { get; set; }

    public DateTime AnsweredAt { get; set; } = DateTime.UtcNow;

    public TestAttempt TestAttempt { get; set; } = null!;

    public Question Question { get; set; } = null!;

    public AnswerOption SelectedOption { get; set; } = null!;
}
