using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Runtime;

/// Live-machine runtime snapshot capture. Captures the current machine's OS,
/// installed tool versions, `$PATH`, opt-in global package inventory, and the
/// *names* of non-secret environment variables. Secret-looking names are
/// dropped, never masked, and values are never captured.
public static class Capture
{
    /// Tools probed by default. Order here is the display order before sorting.
    private static readonly (string Tool, string[] Args)[] ToolProbes =
    {
        ("node", new[] { "-v" }),
        ("python3", new[] { "--version" }),
        ("python", new[] { "--version" }),
        ("go", new[] { "version" }),
        ("rustc", new[] { "-V" }),
        ("java", new[] { "-version" }),
        ("ruby", new[] { "-v" }),
        ("php", new[] { "-v" }),
        ("perl", new[] { "-v" }),
        ("cc", new[] { "--version" }),
        ("git", new[] { "--version" }),
    };

    private static readonly Regex VersionRe = new(@"(\d+\.\d+(?:\.\d+)?)", RegexOptions.Compiled);

    /// Collapse a leading `$HOME` to `~` so snapshots don't leak usernames and
    /// stay comparable across machines.
    private static string CollapseHome(string p)
    {
        var home = Environment.GetEnvironmentVariable("HOME") ?? "";
        if (home.Length > 0 && (p == home || p.StartsWith(home + "/", StringComparison.Ordinal)))
            return "~" + p[home.Length..];
        return p;
    }

    /// Ordered, de-duplicated `$PATH` entries with `$HOME` collapsed.
    private static List<string> CollectPath()
    {
        var raw = Environment.GetEnvironmentVariable("PATH") ?? "";
        var seen = new HashSet<string>();
        var result = new List<string>();
        foreach (var part in raw.Split(':'))
        {
            if (part.Length == 0)
                continue;
            var entry = CollapseHome(part);
            if (seen.Add(entry))
                result.Add(entry);
        }
        return result;
    }

    /// Non-secret env var NAMES only, sorted. Secret-looking names are dropped.
    private static List<string> CollectEnvFlagNames()
    {
        var names = Environment.GetEnvironmentVariables().Keys
            .Cast<object>()
            .Select(k => k.ToString() ?? "")
            .Where(name => !EnvironmentVariable.IsSecretName(name))
            .ToList();
        names.Sort(StringComparer.Ordinal);
        return names;
    }

    private static string? Run(string tool, string[] args, bool redirectErr = true)
    {
        try
        {
            var startInfo = new ProcessStartInfo(tool)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = redirectErr,
                UseShellExecute = false,
            };
            foreach (var arg in args)
                startInfo.ArgumentList.Add(arg);
            using var process = Process.Start(startInfo);
            if (process is null)
                return null;
            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = redirectErr ? process.StandardError.ReadToEnd() : "";
            process.WaitForExit();
            return stdout + stderr;
        }
        catch
        {
            return null;
        }
    }

    /// Probe one CLI's version; returns null when the tool isn't installed.
    private static string? ProbeVersion(string tool, string[] args)
    {
        var output = Run(tool, args);
        if (output is null)
            return null;
        var match = VersionRe.Match(output);
        return match.Success ? match.Groups[1].Value : null;
    }

    /// Locate which PATH directory a command resolves from, `$HOME` collapsed.
    private static string ResolveFrom(string tool)
    {
        var stdout = Run("which", new[] { tool }, redirectErr: false);
        if (stdout is null)
            return "";
        var first = stdout.Split('\n').FirstOrDefault(l => l.Trim().Length > 0);
        if (first is null)
            return "";
        var dir = Path.GetDirectoryName(first.Trim()) ?? "";
        return CollapseHome(dir);
    }

    /// Probe every known tool; only installed ones appear, sorted by name.
    private static List<ToolInfo> CollectTools()
    {
        var tools = ToolProbes
            .Select(probe => (probe.Tool, Version: ProbeVersion(probe.Tool, probe.Args)))
            .Where(r => r.Version is not null)
            .Select(r => new ToolInfo
            {
                Tool = r.Tool,
                Version = r.Version!,
                ResolvedFrom = ResolveFrom(r.Tool),
            })
            .ToList();
        tools.Sort((a, b) => string.CompareOrdinal(a.Tool, b.Tool));
        return tools;
    }

    /// Global package inventory, opt-in because it is slow. Best-effort per
    /// ecosystem (currently npm).
    private static Dictionary<string, List<GlobalPackage>> CollectGlobals()
    {
        var globals = new Dictionary<string, List<GlobalPackage>>();
        var stdout = Run("npm", new[] { "ls", "-g", "--depth=0", "--json" }, redirectErr: false);
        if (stdout is not null)
        {
            var pkgs = ParseNpmGlobals(stdout);
            if (pkgs.Count > 0)
                globals["npm"] = pkgs;
        }
        return globals;
    }

    /// Parse `npm ls -g --json` into a name/version list; tolerant of partial JSON.
    private static List<GlobalPackage> ParseNpmGlobals(string stdout)
    {
        try
        {
            using var doc = JsonDocument.Parse(stdout);
            if (!doc.RootElement.TryGetProperty("dependencies", out var deps) ||
                deps.ValueKind != JsonValueKind.Object)
            {
                return new List<GlobalPackage>();
            }
            var pkgs = deps.EnumerateObject()
                .Select(p => new GlobalPackage
                {
                    Name = p.Name,
                    Version = p.Value.TryGetProperty("version", out var v) && v.ValueKind == JsonValueKind.String
                        ? v.GetString() ?? ""
                        : "",
                })
                .ToList();
            pkgs.Sort((a, b) => string.CompareOrdinal(a.Name, b.Name));
            return pkgs;
        }
        catch (JsonException)
        {
            return new List<GlobalPackage>();
        }
    }

    /// OS release string (`uname -r` on unix), best-effort.
    private static string OsRelease()
    {
        var stdout = Run("uname", new[] { "-r" }, redirectErr: false);
        var trimmed = stdout?.Trim();
        return string.IsNullOrEmpty(trimmed) ? "unknown" : trimmed;
    }

    /// OS/arch strings matching Node's `process.platform` / `process.arch`
    /// (the reference CLI's snapshot shape).
    private static string OsPlatform()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            return "darwin";
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            return "linux";
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return "win32";
        if (RuntimeInformation.IsOSPlatform(OSPlatform.FreeBSD))
            return "freebsd";
        return "unknown";
    }

    private static string OsArch() => RuntimeInformation.OSArchitecture switch
    {
        Architecture.X64 => "x64",
        Architecture.X86 => "ia32",
        Architecture.Arm64 => "arm64",
        Architecture.Arm => "arm",
        _ => "unknown",
    };

    /// Capture this machine's live runtime. `globals` opts into the slow
    /// package inventory.
    public static RuntimeSnapshot CaptureSnapshot(bool globals) =>
        new()
        {
            Schema = SnapshotSchema.Value,
            CapturedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(),
            Os = new OsInfo
            {
                Platform = OsPlatform(),
                Arch = OsArch(),
                Release = OsRelease(),
            },
            Tools = CollectTools(),
            Path = CollectPath(),
            Globals = globals ? CollectGlobals() : new Dictionary<string, List<GlobalPackage>>(),
            EnvFlagNames = CollectEnvFlagNames(),
        };
}
