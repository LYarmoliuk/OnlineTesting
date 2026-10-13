namespace OnlineTesting.Api.Models;

public class TestAttempt
{
    public int Id { get; set; }

    public int TestId { get; set; }

    // Тимчасовий токен доступу до спроби, не автентифікація студента.
    public Guid AccessToken { get; set; } = Guid.NewGuid();

    public DateTime StartedAt { get; set; } = DateTime.UtcNow;

    public DateTime? CompletedAt { get; set; }

    public TestAttemptStatus Status { get; set; } = TestAttemptStatus.InProgress;

    // Фіксується сервером під час завершення спроби.
    public int? Score { get; set; }

    public Test Test { get; set; } = null!;

    public ICollection<StudentAnswer> Answers { get; set; } = new List<StudentAnswer>();
}
