using System.Text;
using System.Text.RegularExpressions;

namespace Envdoctor.Utils;

/// A tiny glob-to-regex converter for matching variable names and file paths
/// against config patterns (`ignoreVariables: ["AWS_*"]`, environment
/// overrides, etc.). Supports `*` (within a segment), `**`, and `?`.
public static class Glob
{
    private static readonly Dictionary<string, Regex> Cache = new();
    private static readonly object CacheLock = new();

    public static Regex GlobToRegex(string pattern)
    {
        lock (CacheLock)
        {
            if (Cache.TryGetValue(pattern, out var cached))
                return cached;

            var sb = new StringBuilder(pattern.Length * 2);
            sb.Append('^');
            var i = 0;
            while (i < pattern.Length)
            {
                var c = pattern[i];
                switch (c)
                {
                    case '*':
                        if (i + 1 < pattern.Length && pattern[i + 1] == '*')
                        {
                            sb.Append(".*");
                            i += 2;
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
                    default:
                        if (".+?^${}()|[]\\".Contains(c))
                            sb.Append('\\');
                        sb.Append(c);
                        i += 1;
                        break;
                }
            }
            sb.Append('$');

            var re = new Regex(sb.ToString(), RegexOptions.Compiled);
            Cache[pattern] = re;
            return re;
        }
    }

    public static bool MatchesGlob(string pattern, string value) => GlobToRegex(pattern).IsMatch(value);

    public static bool MatchesAnyGlob(IReadOnlyList<string> patterns, string value) =>
        patterns.Any(p => MatchesGlob(p, value));
}
