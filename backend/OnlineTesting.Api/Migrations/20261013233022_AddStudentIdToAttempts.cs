using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace OnlineTesting.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddStudentIdToAttempts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "StudentId",
                table: "TestAttempts",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "StudentId",
                table: "TestAttempts");
        }
    }
}
