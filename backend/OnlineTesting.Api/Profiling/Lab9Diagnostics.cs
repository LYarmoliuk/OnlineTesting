using System.Diagnostics;

namespace OnlineTesting.Api.Profiling;

public static class Lab9Diagnostics
{
    public const string SourceName = "OnlineTesting.Api.Lab9";
    public static readonly ActivitySource ActivitySource = new(SourceName);
}
