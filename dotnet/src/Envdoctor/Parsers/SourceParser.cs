using System.Text;
using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Parsers;

/// Scans for `process.env.NAME`, `process.env['NAME']`, and
/// `import.meta.env.NAME` usages. Comments and string literals are stripped
/// first (a state machine that understands quotes, escape sequences, template
/// literals, and `${...}` interpolation) so documented/string occurrences
/// don't create false positives.
public sealed class SourceParser : IParser
{
    private static readonly Regex[] Patterns =
    {
        new(@"\bprocess\.env\.([A-Za-z_$][A-Za-z0-9_$]*)", RegexOptions.Compiled),
        new(@"\bprocess\.env\[['""]([A-Za-z_$][A-Za-z0-9_$]*)['""]\]", RegexOptions.Compiled),
        new(@"\bimport\.meta\.env\.([A-Za-z_$][A-Za-z0-9_$]*)", RegexOptions.Compiled),
    };

    private readonly HashSet<string> _extSet;

    public SourceParser(IReadOnlyList<string> extensions)
    {
        _extSet = extensions
            .Select(e => e.TrimStart('.').ToLowerInvariant())
            .ToHashSet();
    }

    public string Id => "source";

    public bool MatchPath(string filePath)
    {
        var ext = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
        return ext.Length > 0 && _extSet.Contains(ext);
    }

    public EnvironmentFile Parse(string content, string filePath)
    {
        var stripped = StripComments(content);
        var usages = new List<EnvironmentVariable>();

        foreach (var re in Patterns)
        {
            foreach (Match match in re.Matches(stripped))
            {
                var name = match.Groups[1].Value;
                var origin = new Origin
                {
                    FilePath = filePath,
                    Line = LineNumberAt(stripped, match.Index),
                    Kind = OriginKind.Usage,
                    Format = OriginFormat.Source,
                };
                usages.Add(EnvironmentVariable.Create(name, null, new List<Origin> { origin }));
            }
        }

        return new EnvironmentFile
        {
            FilePath = filePath,
            Format = FileFormat.Source,
            Variables = new List<EnvironmentVariable>(),
            Usages = EnvironmentVariable.Merge(usages),
        };
    }

    /// 1-based line number for a character offset in `text`.
    private static int LineNumberAt(string text, int offset)
    {
        var end = Math.Min(offset, text.Length);
        var line = 1;
        for (var i = 0; i < end; i++)
        {
            if (text[i] == '\n')
                line++;
        }
        return line;
    }

    private enum Mode
    {
        Code,
        CodeTpl,
        Sq,
        Dq,
        Tq,
    }

    private sealed class Frame
    {
        public Mode Mode;
        public int TplDepth;
        /// For string frames: when true, the string content is preserved
        /// verbatim (used for computed-property access like
        /// `process.env["KEY"]` where the string is a variable name, not a
        /// literal we want to blank out).
        public bool Preserve;
    }

    /// Replace comments and string-literal *contents* with spaces while
    /// preserving line structure. Template-literal `${...}` interpolation is
    /// treated as code so `process.env.X` inside it is still found.
    private static string StripComments(string code)
    {
        var outSb = new StringBuilder(code.Length);
        var len = code.Length;
        var i = 0;
        var stack = new List<Frame> { new() { Mode = Mode.Code } };

        void SkipLineComment()
        {
            while (i < len && code[i] != '\n')
            {
                outSb.Append(' ');
                i++;
            }
        }

        void SkipBlockComment()
        {
            outSb.Append("  ");
            i += 2;
            while (i < len)
            {
                if (code[i] == '*' && i + 1 < len && code[i + 1] == '/')
                {
                    outSb.Append("  ");
                    i += 2;
                    return;
                }
                outSb.Append(code[i] == '\n' ? '\n' : ' ');
                i++;
            }
        }

        while (i < len)
        {
            var c = code[i];
            char? next = i + 1 < len ? code[i + 1] : null;
            var top = stack[^1];
            var mode = top.Mode;

            switch (mode)
            {
                case Mode.Code:
                case Mode.CodeTpl:
                    if (c is '\'' or '"' or '`')
                    {
                        var stringMode = c switch
                        {
                            '`' => Mode.Tq,
                            '"' => Mode.Dq,
                            _ => Mode.Sq,
                        };
                        // A string that immediately follows `[` is a
                        // computed-property key.
                        var preserve = c != '`' && i > 0 && code[i - 1] == '[';
                        stack.Add(new Frame { Mode = stringMode, Preserve = preserve });
                        outSb.Append(c);
                        i++;
                    }
                    else if (c == '/' && next == '/')
                    {
                        SkipLineComment();
                    }
                    else if (c == '/' && next == '*')
                    {
                        SkipBlockComment();
                    }
                    else if (mode == Mode.CodeTpl)
                    {
                        if (c == '{')
                        {
                            top.TplDepth++;
                        }
                        else if (c == '}')
                        {
                            top.TplDepth--;
                            if (top.TplDepth == 0)
                                stack.RemoveAt(stack.Count - 1);
                        }
                        outSb.Append(c);
                        i++;
                    }
                    else
                    {
                        outSb.Append(c);
                        i++;
                    }
                    break;
                case Mode.Tq:
                    if (c == '\\' && i + 1 < len)
                    {
                        outSb.Append(c);
                        outSb.Append(code[i + 1]);
                        i += 2;
                    }
                    else if (c == '`')
                    {
                        stack.RemoveAt(stack.Count - 1);
                        outSb.Append(c);
                        i++;
                    }
                    else if (c == '$' && next == '{')
                    {
                        outSb.Append("${");
                        i += 2;
                        stack.Add(new Frame { Mode = Mode.CodeTpl, TplDepth = 1 });
                    }
                    else
                    {
                        // Template-literal content (not in interpolation) is blanked.
                        outSb.Append(' ');
                        i++;
                    }
                    break;
                case Mode.Sq:
                case Mode.Dq:
                {
                    var quote = mode == Mode.Sq ? '\'' : '"';
                    var preserve = top.Preserve;
                    if (c == '\\' && i + 1 < len)
                    {
                        if (preserve)
                        {
                            outSb.Append(c);
                            outSb.Append(code[i + 1]);
                        }
                        else
                        {
                            outSb.Append("  ");
                        }
                        i += 2;
                    }
                    else if (c == quote)
                    {
                        outSb.Append(c);
                        i++;
                        stack.RemoveAt(stack.Count - 1);
                    }
                    else if (preserve)
                    {
                        // Preserve computed-property key content verbatim.
                        outSb.Append(c);
                        i++;
                    }
                    else
                    {
                        // Regular string literal content — blank it out.
                        outSb.Append(' ');
                        i++;
                    }
                    break;
                }
            }
        }

        return outSb.ToString();
    }
}
