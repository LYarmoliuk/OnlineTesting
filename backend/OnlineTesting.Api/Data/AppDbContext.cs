
using Microsoft.EntityFrameworkCore;
using OnlineTesting.Api.Models;

namespace OnlineTesting.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options)
    : DbContext(options)
{
    public DbSet<Test> Tests => Set<Test>();

    public DbSet<Question> Questions => Set<Question>();

    public DbSet<AnswerOption> AnswerOptions => Set<AnswerOption>();

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
    }
}
