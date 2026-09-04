using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using Envdoctor.Config;
using Envdoctor.Utils;

namespace Envdoctor.Core;

/// File discovery for the audit pipeline.
public static class Discover
{
    /// Always-ignored basenames during discovery.
    private static readonly string[] AlwaysIgnored =
    {
        "node_modules",
        ".git",
        "dist",
        "build",
        ".next",
        ".turbo",
        ".vercel",
        ".netlify",
        "coverage",
        ".nyc_output",
        "target",
        ".cargo",
        "vendor",
        "Pods",
        ".idea",
        ".vscode",
        "*.log",
        "*.tmp",
        "*.swp",
        "*.swo",
        "~*",
        "*.DS_Store",
    };

    /// Directories that are never descended into (union of the reference
    /// implementations' ignore lists; none of them hold project env files).
    private static readonly HashSet<string> IgnoredDirs = new(StringComparer.Ordinal)
    {
        "node_modules",
        ".git",
        "dist",
        "build",
        "coverage",
        ".next",
        ".nuxt",
        ".venv",
        "vendor",
        ".Trash",
        "Library",
        ".cache",
        ".npm",
        ".turbo",
        ".vercel",
        ".netlify",
        ".nyc_output",
        "target",
        ".cargo",
        "Pods",
        ".idea",
        ".vscode",
    };

    /// Git-aware file filter: tracks whether we're in a repo and can run
    /// `git check-ignore` / `git diff`.
    public sealed class GitFilter
    {
        public string Root { get; }
        public bool IsRepo { get; }

        public GitFilter(string root)
        {
            Root = root;
            IsRepo = CheckRepo(root);
        }

        private static bool CheckRepo(string root)
        {
            try
            {
                using var process = Process.Start(new ProcessStartInfo("git", "rev-parse --is-inside-work-tree")
                {
                    WorkingDirectory = root,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                });
                process?.WaitForExit();
                return process?.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }

        /// Should this file be skipped? Returns true to skip.
        public bool ShouldSkip(string path)
        {
            // Check always-ignored patterns first (fast path)
            var fileName = Path.GetFileName(path);
            foreach (var pattern in AlwaysIgnored)
            {
                if (Glob.MatchesGlob(pattern, fileName))
                    return true;
            }

            // If not a git repo, rely on patterns only
            if (!IsRepo)
                return false;

            var rel = RelativeTo(Root, path);
            if (rel is null)
                return false;

            // Skip if git ignores it (via .gitignore)
            try
            {
                var startInfo = new ProcessStartInfo("git")
                {
                    WorkingDirectory = Root,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                };
                startInfo.ArgumentList.Add("check-ignore");
                startInfo.ArgumentList.Add("-q");
                startInfo.ArgumentList.Add(rel);
                using var process = Process.Start(startInfo);
                process?.WaitForExit();
                return process?.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }
    }

    /// Path relative to root using forward slashes; null when not under root.
    public static string? RelativeTo(string root, string path)
    {
        var prefix = root.EndsWith(Path.DirectorySeparatorChar) ? root : root + Path.DirectorySeparatorChar;
        if (!path.StartsWith(prefix, StringComparison.Ordinal))
            return path == root ? "" : null;
        return path[prefix.Length..].Replace(Path.DirectorySeparatorChar, '/');
    }

    /// Discover all files matching the configured glob patterns.
    public static List<string> DiscoverFiles(string root, EnvdoctorConfig config)
    {
        var patterns = config.EnvFilePatterns
            .Concat(config.ComposeFilePatterns)
            .Concat(config.ActionsFilePatterns)
            .Concat(config.K8sFilePatterns)
            .Select(PathGlob.ToRegex)
            .ToList();

        var gitFilter = new GitFilter(root);
        var results = new List<string>();

        foreach (var path in WalkFiles(root))
        {
            var rel = RelativeTo(root, path);
            if (rel is null)
                continue;
            if (!patterns.Any(re => re.IsMatch(rel)))
                continue;
            if (gitFilter.ShouldSkip(path))
                continue;
            results.Add(path);
        }

        results.Sort(StringComparer.Ordinal);
        return results.Distinct(StringComparer.Ordinal).ToList();
    }

    /// Discover source files for usage scanning.
    public static List<string> DiscoverSourceFiles(string root, EnvdoctorConfig config)
    {
        var extensions = config.SourceExtensions
            .Select(e => e.TrimStart('.'))
            .ToHashSet(StringComparer.Ordinal);
        var gitFilter = new GitFilter(root);
        var results = new List<string>();

        foreach (var path in WalkFiles(root))
        {
            if (gitFilter.ShouldSkip(path))
                continue;
            var ext = Path.GetExtension(path).TrimStart('.');
            if (ext.Length > 0 && extensions.Contains(ext))
                results.Add(path);
        }

        results.Sort(StringComparer.Ordinal);
        return results.Distinct(StringComparer.Ordinal).ToList();
    }

    /// Walk every file under root, pruning always-ignored directories.
    private static IEnumerable<string> WalkFiles(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            var dir = pending.Pop();
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(dir);
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (IOException)
            {
                continue;
            }
            foreach (var entry in entries)
            {
                var name = Path.GetFileName(entry);
                if (Directory.Exists(entry))
                {
                    if (!IgnoredDirs.Contains(name))
                        pending.Push(entry);
                }
                else
                {
                    yield return entry;
                }
            }
        }
    }

    /// Get files changed since a commit/branch.
    public static List<string> ChangedFilesSince(string root, string since) =>
        GitNameOnly(root, new[] { "diff", "--name-only", since });

    /// Get currently staged files.
    public static List<string> StagedFiles(string root) =>
        GitNameOnly(root, new[] { "diff", "--name-only", "--cached" });

    private static List<string> GitNameOnly(string root, string[] args)
    {
        try
        {
            var startInfo = new ProcessStartInfo("git")
            {
                WorkingDirectory = root,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            foreach (var arg in args)
                startInfo.ArgumentList.Add(arg);
            using var process = Process.Start(startInfo);
            if (process is null)
                return new List<string>();
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
                return new List<string>();
            return output
                .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Select(l => Path.Combine(root, l.TrimEnd('\r')))
                .ToList();
        }
        catch
        {
            return new List<string>();
        }
    }
}

/// Translate a path glob (with `**`, `*`, `?`, and `{a,b}` braces) to a regex
/// matched against a root-relative, forward-slash path.
public static class PathGlob
{
    private static readonly Dictionary<string, Regex> Cache = new(StringComparer.Ordinal);

    public static Regex ToRegex(string pattern)
    {
        lock (Cache)
        {
            if (Cache.TryGetValue(pattern, out var cached))
                return cached;
            var re = new Regex(Convert(pattern), RegexOptions.Compiled);
            Cache[pattern] = re;
            return re;
        }
    }

    private static string Convert(string pattern)
    {
        var sb = new StringBuilder("^");
        var i = 0;
        while (i < pattern.Length)
        {
            var c = pattern[i];
            switch (c)
            {
                case '*':
                    if (i + 1 < pattern.Length && pattern[i + 1] == '*')
                    {
                        // `**/`: zero or more whole segments; bare `**`: anything.
                        if (i + 2 < pattern.Length && pattern[i + 2] == '/')
                        {
                            sb.Append("(?:.*/)?");
                            i += 3;
                        }
                        else
                        {
                            sb.Append(".*");
                            i += 2;
                        }
                    }
                    else
                    {
                        sb.Append("[^/]*");
                        i += 1;
                    }
                    break;
                case '?':
                    sb.Append("[^/]");
                    i += 1;
                    break;
                case '{':
                {
                    var close = FindBraceEnd(pattern, i);
                    if (close < 0)
                    {
                        sb.Append("\\{");
                        i += 1;
                        break;
                    }
                    var inner = pattern[(i + 1)..close];
                    var options = inner.Split(',').Select(o => Regex.Escape(o));
                    sb.Append("(?:").Append(string.Join('|', options)).Append(')');
                    i = close + 1;
                    break;
                }
                default:
                    sb.Append(Regex.Escape(c.ToString()));
                    i += 1;
                    break;
            }
        }
        sb.Append('$');
        return sb.ToString();
    }

    private static int FindBraceEnd(string pattern, int start)
    {
        for (var i = start + 1; i < pattern.Length; i++)
        {
            if (pattern[i] == '}')
                return i;
        }
        return -1;
    }
}
