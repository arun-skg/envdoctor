using System.Text.RegularExpressions;

namespace Envdoctor.Parsers;

/// Helpers for scanning shell-style variable interpolation in YAML-based
/// formats (docker-compose, GitHub Actions). Shared because both formats use
/// `$VAR` / `${VAR}` and need 1-based line numbers for origins.
public static class YamlInterp
{
    private static readonly Regex InterpRe = new(
        @"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)(?:\s*[:-?+][^}]*)?\}|([A-Za-z_][A-Za-z0-9_]*))",
        RegexOptions.Compiled);

    /// Compute the 1-based line number of a character offset in `content`.
    public static int LineForOffset(string content, int offset)
    {
        var end = Math.Min(offset, content.Length);
        var line = 1;
        for (var i = 0; i < end; i++)
        {
            if (content[i] == '\n')
                line++;
        }
        return line;
    }

    public sealed record Interpolation(string Name, int Line);

    /// Scan `content` for `$VAR` and `${VAR}` interpolations, honoring the
    /// `$$` escape. `{...}` modifiers (e.g. `${VAR:-x}`) are stripped — only
    /// the name is kept.
    public static List<Interpolation> ScanInterpolations(string content)
    {
        // Protect escaped `$$` (same length, so offsets stay valid) so the second
        // `$` is never mistaken for a real interpolation.
        var protectedContent = content.Replace("$$", "  ");
        var results = new List<Interpolation>();
        foreach (Match match in InterpRe.Matches(protectedContent))
        {
            var name = match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value;
            results.Add(new Interpolation(name, LineForOffset(content, match.Index)));
        }
        return results;
    }
}
