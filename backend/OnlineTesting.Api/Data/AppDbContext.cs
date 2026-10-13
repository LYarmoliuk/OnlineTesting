
using Microsoft.EntityFrameworkCore;

namespace OnlineTesting.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options)
    : DbContext(options)
{
}
