using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Envdoctor.Models;
using Envdoctor.Utils;

namespace Envdoctor.Runtime;

/// Portable snapshot token: `base64url(gzip(json))` with an `envd1:` prefix.
public static class Token
{
    private const string Prefix = "envd1:";

    /// Serialize a snapshot to compact JSON with the reference property order.
    public static string SnapshotToJson(RuntimeSnapshot snapshot)
    {
        var globals = new JsonObject();
        foreach (var (eco, packages) in snapshot.Globals)
        {
            globals.Add(eco, packages
                .Select(p => (object)new JsonObject { { "name", p.Name }, { "version", p.Version } })
                .ToList());
        }
        return Json.Compact(new JsonObject
        {
            { "schema", snapshot.Schema },
            { "capturedAt", snapshot.CapturedAt },
            {
                "os", new JsonObject
                {
                    { "platform", snapshot.Os.Platform },
                    { "arch", snapshot.Os.Arch },
                    { "release", snapshot.Os.Release },
                }
            },
            {
                "tools", snapshot.Tools
                    .Select(t => (object)new JsonObject
                    {
                        { "tool", t.Tool },
                        { "version", t.Version },
                        { "resolvedFrom", t.ResolvedFrom },
                    })
                    .ToList()
            },
            { "path", snapshot.Path.Cast<object?>().ToList() },
            { "globals", globals },
            { "envFlagNames", snapshot.EnvFlagNames.Cast<object?>().ToList() },
        });
    }

    /// Encode a snapshot into a single-line, paste-safe token.
    public static string EncodeToken(RuntimeSnapshot snapshot)
    {
        var json = Encoding.UTF8.GetBytes(SnapshotToJson(snapshot));
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Optimal, leaveOpen: true))
            gzip.Write(json, 0, json.Length);
        return Prefix + Base64UrlEncode(output.ToArray());
    }

    /// Decode a token back into a snapshot. Errors clearly on malformed or
    /// too-new input.
    public static RuntimeSnapshot DecodeToken(string token)
    {
        var trimmed = token.Trim();
        if (!trimmed.StartsWith(Prefix, StringComparison.Ordinal))
            throw new SnapshotTokenException("Not an envdoctor snapshot token (missing envd1: prefix).");

        RuntimeSnapshot snapshot;
        try
        {
            var gzipped = Base64UrlDecode(trimmed[Prefix.Length..]);
            using var input = new MemoryStream(gzipped);
            using var gzip = new GZipStream(input, CompressionMode.Decompress);
            using var reader = new StreamReader(gzip, Encoding.UTF8);
            snapshot = ParseSnapshot(JsonDocument.Parse(reader.ReadToEnd()).RootElement);
        }
        catch (Exception)
        {
            throw new SnapshotTokenException("Corrupt snapshot token: could not decode.");
        }
        AssertReadable(snapshot);
        return snapshot;
    }

    /// Parse raw JSON (from a `--output` file) into a validated snapshot.
    public static RuntimeSnapshot ParseSnapshotJson(string text)
    {
        RuntimeSnapshot snapshot;
        try
        {
            snapshot = ParseSnapshot(JsonDocument.Parse(text).RootElement);
        }
        catch (SnapshotTokenException)
        {
            throw;
        }
        catch (Exception)
        {
            throw new SnapshotTokenException("Invalid snapshot JSON.");
        }
        AssertReadable(snapshot);
        return snapshot;
    }

    /// Reject snapshots from a newer schema than this build understands.
    private static void AssertReadable(RuntimeSnapshot snapshot)
    {
        if (string.CompareOrdinal(snapshot.Schema, SnapshotSchema.Value) > 0)
        {
            throw new SnapshotTokenException(
                $"Snapshot schema {snapshot.Schema} is newer than this envdoctor ({SnapshotSchema.Value}). Upgrade to compare it.");
        }
    }

    private static RuntimeSnapshot ParseSnapshot(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object)
            throw new SnapshotTokenException("Invalid snapshot JSON.");

        var snapshot = new RuntimeSnapshot();
        if (el.TryGetProperty("schema", out var schema) && schema.ValueKind == JsonValueKind.String)
            snapshot.Schema = schema.GetString() ?? "";
        if (el.TryGetProperty("capturedAt", out var capturedAt) && capturedAt.ValueKind == JsonValueKind.String)
            snapshot.CapturedAt = capturedAt.GetString() ?? "";
        if (el.TryGetProperty("os", out var os) && os.ValueKind == JsonValueKind.Object)
        {
            snapshot.Os = new OsInfo
            {
                Platform = GetStr(os, "platform"),
                Arch = GetStr(os, "arch"),
                Release = GetStr(os, "release"),
            };
        }
        if (el.TryGetProperty("tools", out var tools) && tools.ValueKind == JsonValueKind.Array)
        {
            snapshot.Tools = tools.EnumerateArray()
                .Select(t => new ToolInfo
                {
                    Tool = GetStr(t, "tool"),
                    Version = GetStr(t, "version"),
                    ResolvedFrom = GetStr(t, "resolvedFrom"),
                })
                .ToList();
        }
        if (el.TryGetProperty("path", out var path) && path.ValueKind == JsonValueKind.Array)
            snapshot.Path = path.EnumerateArray().Select(p => p.GetString() ?? "").ToList();
        if (el.TryGetProperty("globals", out var globals) && globals.ValueKind == JsonValueKind.Object)
        {
            snapshot.Globals = globals.EnumerateObject().ToDictionary(
                eco => eco.Name,
                eco => eco.Value.ValueKind == JsonValueKind.Array
                    ? eco.Value.EnumerateArray()
                        .Select(p => new GlobalPackage { Name = GetStr(p, "name"), Version = GetStr(p, "version") })
                        .ToList()
                    : new List<GlobalPackage>());
        }
        if (el.TryGetProperty("envFlagNames", out var flags) && flags.ValueKind == JsonValueKind.Array)
            snapshot.EnvFlagNames = flags.EnumerateArray().Select(p => p.GetString() ?? "").ToList();
        return snapshot;
    }

    private static string GetStr(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object &&
        el.TryGetProperty(name, out var v) &&
        v.ValueKind == JsonValueKind.String
            ? v.GetString() ?? ""
            : "";

    private static string Base64UrlEncode(byte[] data) =>
        Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] Base64UrlDecode(string input)
    {
        var b64 = input.Replace('-', '+').Replace('_', '/');
        switch (b64.Length % 4)
        {
            case 2: b64 += "=="; break;
            case 3: b64 += "="; break;
        }
        return Convert.FromBase64String(b64);
    }
}

public sealed class SnapshotTokenException : Exception
{
    public SnapshotTokenException(string message) : base(message) { }
}
