using Microsoft.EntityFrameworkCore;
using OnlineTesting.Api.Models;

namespace OnlineTesting.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options)
    : DbContext(options)
{
    public DbSet<Test> Tests => Set<Test>();
    public DbSet<Question> Questions => Set<Question>();
    public DbSet<AnswerOption> AnswerOptions => Set<AnswerOption>();
    public DbSet<TestAttempt> TestAttempts => Set<TestAttempt>();
    public DbSet<StudentAnswer> StudentAnswers => Set<StudentAnswer>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Test>()
            .HasMany(test => test.Questions)
            .WithOne(question => question.Test)
            .HasForeignKey(question => question.TestId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<Question>()
            .HasMany(question => question.AnswerOptions)
            .WithOne(option => option.Question)
            .HasForeignKey(option => option.QuestionId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<Question>()
            .HasIndex(question => new { question.TestId, question.Order });

modelBuilder.Entity<TestAttempt>()
    .HasOne(attempt => attempt.Test)
    .WithMany(test => test.Attempts)
    .HasForeignKey(attempt => attempt.TestId)
    .OnDelete(DeleteBehavior.Cascade);
    
        modelBuilder.Entity<TestAttempt>()
            .Property(attempt => attempt.Status)
            .HasConversion<string>()
            .HasMaxLength(20);

        modelBuilder.Entity<TestAttempt>()
            .HasIndex(attempt => attempt.AccessToken)
            .IsUnique();

        modelBuilder.Entity<TestAttempt>()
            .HasMany(attempt => attempt.Answers)
            .WithOne(answer => answer.TestAttempt)
            .HasForeignKey(answer => answer.TestAttemptId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<StudentAnswer>()
            .HasIndex(answer => new
            {
                answer.TestAttemptId,
                answer.QuestionId
            })
            .IsUnique();

        modelBuilder.Entity<StudentAnswer>()
            .HasOne(answer => answer.Question)
            .WithMany()
            .HasForeignKey(answer => answer.QuestionId)
            .OnDelete(DeleteBehavior.Restrict);

        modelBuilder.Entity<StudentAnswer>()
            .HasOne(answer => answer.SelectedOption)
            .WithMany()
            .HasForeignKey(answer => answer.SelectedOptionId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}