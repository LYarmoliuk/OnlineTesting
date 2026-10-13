
using System.ComponentModel.DataAnnotations;

namespace OnlineTesting.Api.Models;

public class Test
{
    public ICollection<TestAttempt> Attempts { get; set; }
    = new List<TestAttempt>();
    
    public int Id { get; set; }

    [Required]
    [MaxLength(150)]
    public string Title { get; set; } = string.Empty;

    [MaxLength(2000)]
    public string Description { get; set; } = string.Empty;

    public bool IsPublished { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Question> Questions { get; set; } = new List<Question>();
}
