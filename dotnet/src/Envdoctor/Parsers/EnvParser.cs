using System.Text;
using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Parsers;

/// Parser for dotenv-style files (`.env`, `.env.local`, `.env.production`, ...).
///
/// Hand-rolled tokenizer: the audit needs every occurrence of a key (to detect
/// duplicates and to attribute origins with line numbers), while `dotenv`
/// silently keeps only the last value for a repeated key.
public sealed class EnvParser : IParser
{
    private static readonly Regex BasenameRe = new(@"^\.env(\..+)?$", RegexOptions.Compiled);
    private static readonly Regex IgnoreDirectiveRe = new(
        @"^#\s*envdoctor:ignore\s+([a-z0-9_,\-\s]+)\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public string Id => "dotenv";

    public bool MatchPath(string filePath) => BasenameRe.IsMatch(Path.GetFileName(filePath));

    public EnvironmentFile Parse(string content, string filePath)
    {
        var environment = EnvironmentLabelForDotenv(filePath);
        var entries = ApplyIgnoreDirectives(ParseDotenv(content), ParseIgnoreDirectives(content));

        var variables = new List<EnvironmentVariable>();
        foreach (var entry in entries)
        {
            var origin = new Origin
            {
                FilePath = filePath,
                Line = entry.Line,
                Kind = OriginKind.Definition,
                Environment = environment,
                Format = OriginFormat.Dotenv,
            };
            variables.Add(EnvironmentVariable.Create(entry.Key, entry.Value, new List<Origin> { origin }, entry.IgnoreRules));
        }

        return new EnvironmentFile
        {
            FilePath = filePath,
            Format = FileFormat.Dotenv,
            Environment = environment,
            Variables = variables,
            Usages = new List<EnvironmentVariable>(),
        };
    }

    /// The environment label derived from a dotenv filename.
    public static string EnvironmentLabelForDotenv(string filePath)
    {
        var baseName = Path.GetFileName(filePath);
        if (baseName == ".env")
            return "development";
        if (baseName == ".env.example")
            return "example";
        var suffix = baseName.StartsWith(".env.") ? baseName[".env.".Length..]
            : baseName.StartsWith(".env") ? baseName[".env".Length..]
            : "";
        if (suffix.Length == 0)
            return "development";
        // `.env.development.local` → development, `.env.test` → test
        if (suffix.EndsWith(".local", StringComparison.Ordinal))
            suffix = suffix[..^".local".Length];
        return suffix.TrimEnd('.');
    }

    private sealed class EnvEntry
    {
        public required string Key;
        public required string Value;
        public int Line;
        public List<string>? IgnoreRules;
    }

    private sealed class IgnoreDirective
    {
        public int Line;
        public List<string> Rules = new();
    }

    private static bool IsKeyChar(char c) =>
        char.IsAsciiLetterOrDigit(c) || c is '_' or '.' or '-';

    /// Parse dotenv content into key/value/line entries. Handles `export `
    /// prefixes, blank lines, full-line comments, inline comments after
    /// unquoted values (respecting `\#` escapes), single/double/backtick
    /// quoting including multiline quoted values, and the common escape
    /// sequences in double-quoted values. Lines without an `=` are ignored,
    /// matching `dotenv` behavior.
    private static List<EnvEntry> ParseDotenv(string content)
    {
        var entries = new List<EnvEntry>();
        var chars = content;
        var len = chars.Length;
        var i = 0;
        var line = 1;

        while (i < len)
        {
            // Skip whitespace and blank lines.
            while (i < len && char.IsWhiteSpace(chars[i]))
            {
                if (chars[i] == '\n')
                    line++;
                i++;
            }
            if (i >= len)
                break;

            // Full-line comment.
            if (chars[i] == '#')
            {
                while (i < len && chars[i] != '\n')
                    i++;
                continue;
            }

            // Optional `export` prefix, allowing spaces and tabs between the
            // prefix and the variable name. The reference requires at least one
            // space or tab after `export` (`/export[ \t]+/`).
            if (i + 6 <= len && chars.Substring(i, 6) == "export")
            {
                var j = i + 6;
                while (j < len && (chars[j] == ' ' || chars[j] == '\t'))
                    j++;
                if (j > i + 6)
                    i = j;
            }

            var startLine = line;

            // Read the key.
            var keyStart = i;
            while (i < len && IsKeyChar(chars[i]))
                i++;
            if (i == keyStart)
            {
                // No key, skip to end of line
                while (i < len && chars[i] != '\n')
                    i++;
                continue;
            }
            var key = chars.Substring(keyStart, i - keyStart);

            // Skip whitespace before `=`.
            while (i < len && chars[i] != '=' && chars[i] != '\n' && char.IsWhiteSpace(chars[i]))
                i++;
            if (i >= len || chars[i] != '=')
            {
                // Malformed line (no `=`); ignore it like dotenv does.
                while (i < len && chars[i] != '\n')
                    i++;
                continue;
            }
            i++; // consume `=`

            // Skip whitespace before the value.
            while (i < len && chars[i] != '\n' && char.IsWhiteSpace(chars[i]))
                i++;

            string value;
            if (i < len && (chars[i] == '"' || chars[i] == '\'' || chars[i] == '`'))
            {
                var quote = chars[i];
                i++;
                var raw = new StringBuilder();
                while (i < len)
                {
                    var c = chars[i];
                    if (c == quote)
                    {
                        i++;
                        break;
                    }
                    if (c == '\\')
                    {
                        if (i + 1 < len)
                        {
                            var next = chars[i + 1];
                            if (quote == '"' && next == 'n')
                            {
                                raw.Append('\n');
                                i += 2;
                                continue;
                            }
                            if (quote == '"' && next == 't')
                            {
                                raw.Append('\t');
                                i += 2;
                                continue;
                            }
                            if (quote == '"' && next == 'r')
                            {
                                raw.Append('\r');
                                i += 2;
                                continue;
                            }
                            if (next is '"' or '\'' or '`' or '\\')
                            {
                                raw.Append(next);
                                i += 2;
                                continue;
                            }
                        }
                        raw.Append(c);
                        i++;
                        continue;
                    }
                    raw.Append(c);
                    if (c == '\n')
                        line++;
                    i++;
                }
                value = raw.ToString();
            }
            else
            {
                // Unquoted value: ends at newline or an unescaped `#`.
                var raw = new StringBuilder();
                while (i < len && chars[i] != '\n')
                {
                    var c = chars[i];
                    if (c == '\\' && i + 1 < len && chars[i + 1] == '#')
                    {
                        raw.Append('#');
                        i += 2;
                        continue;
                    }
                    if (c == '#')
                        break;
                    raw.Append(c);
                    i++;
                }
                value = raw.ToString().TrimEnd();
            }

            entries.Add(new EnvEntry { Key = key, Value = value, Line = startLine });
        }

        return entries;
    }

    /// Parse inline ignore directives placed on the line before a variable
    /// definition: `# envdoctor:ignore unused, weak-secret`.
    private static List<IgnoreDirective> ParseIgnoreDirectives(string content)
    {
        var directives = new List<IgnoreDirective>();
        var lines = content.Split('\n');
        for (var idx = 0; idx < lines.Length; idx++)
        {
            var match = IgnoreDirectiveRe.Match(lines[idx]);
            if (!match.Success)
                continue;
            var rules = match.Groups[1].Value
                .Split(new[] { ',', ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .ToList();
            if (rules.Count > 0)
                directives.Add(new IgnoreDirective { Line = idx + 1, Rules = rules });
        }
        return directives;
    }

    /// Attach pending ignore directives to the first entry that appears after them.
    private static List<EnvEntry> ApplyIgnoreDirectives(List<EnvEntry> entries, List<IgnoreDirective> directives)
    {
        var entryByLine = new Dictionary<int, int>();
        for (var idx = 0; idx < entries.Count; idx++)
            entryByLine[entries[idx].Line] = idx;

        var pending = new List<string>();
        var maxLine = entries.Select(e => e.Line)
            .Concat(directives.Select(d => d.Line))
            .DefaultIfEmpty(1)
            .Max();

        for (var line = 1; line <= maxLine; line++)
        {
            var directive = directives.FirstOrDefault(d => d.Line == line);
            if (directive is not null)
                pending.AddRange(directive.Rules);
            if (entryByLine.TryGetValue(line, out var entryIdx) && pending.Count > 0)
            {
                var entry = entries[entryIdx];
                entry.IgnoreRules = (entry.IgnoreRules ?? new List<string>()).Concat(pending).ToList();
                pending.Clear();
            }
        }

        return entries;
    }
}
