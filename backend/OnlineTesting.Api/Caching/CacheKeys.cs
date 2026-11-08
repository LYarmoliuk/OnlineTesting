namespace OnlineTesting.Api.Caching;

public static class CacheKeys
{
    public const string TestsList = "tests:list:v1";

    public static string QuestionsForTest(int testId) => $"questions:test:{testId}:v1";
}
