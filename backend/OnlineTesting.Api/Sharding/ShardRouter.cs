using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace OnlineTesting.Api.Sharding;

public static class ShardRouter
{
    public const int VirtualBucketCount = 64;
    public static readonly string[] CurrentShards = ["shard-a", "shard-b"];

    public static (string Shard, int Bucket) Route(string studentId, long attemptId, string strategy)
    {
        if (strategy == "single") return ("shard-a", -1);
        if (strategy == "legacy")
        {
            var hash = Hash32(studentId);
            return (CurrentShards[hash % (uint)CurrentShards.Length], -1);
        }

        if (strategy != "bucket") throw new ArgumentException("Unknown shard strategy.", nameof(strategy));
        var bucket = (int)(Hash32($"{studentId}:{attemptId}") % VirtualBucketCount);
        return (Owner(bucket, CurrentShards), bucket);
    }

    // Rendezvous ownership keeps most buckets on their original shard when a node is added.
    public static string Owner(int bucket, IReadOnlyList<string> shards)
    {
        if (shards.Count == 0) throw new ArgumentException("At least one shard is required.", nameof(shards));
        var best = shards[0];
        ulong bestScore = 0;
        foreach (var shard in shards)
        {
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{bucket}:{shard}"));
            var score = BinaryPrimitives.ReadUInt64BigEndian(bytes);
            if (score > bestScore || (score == bestScore && string.CompareOrdinal(shard, best) < 0))
            {
                best = shard;
                bestScore = score;
            }
        }
        return best;
    }

    public static uint Hash32(string value) =>
        BinaryPrimitives.ReadUInt32BigEndian(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
