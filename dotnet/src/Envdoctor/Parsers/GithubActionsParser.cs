using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Parsers;

/// Parser for GitHub Actions workflow files (`.github/workflows/*.{yml,yaml}`).
///
/// Definitions come from `env:` blocks at the workflow, job, and step level.
/// `${{ secrets.NAME }}` / `${{ vars.NAME }}` and `$VAR` / `${VAR}`
/// interpolations anywhere in the file become usages.
public sealed class GithubActionsParser : IParser
{
    private static readonly Regex SecretRefRe = new(
        @"\$\{\{\s*(secrets|vars)\.([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}",
        RegexOptions.Compiled);
    private static readonly Regex YamlExtRe = new(@"\.(ya?ml)$", RegexOptions.Compiled);

    public string Id => "github-actions";

    public bool MatchPath(string filePath)
    {
        var baseName = Path.GetFileName(filePath);
        var isWorkflow = filePath.Contains("/.github/workflows/", StringComparison.Ordinal);
        return isWorkflow && YamlExtRe.IsMatch(baseName);
    }

    public EnvironmentFile Parse(string content, string filePath)
    {
        var doc = YamlFacade.LoadFirst(content);
        var variables = new List<EnvironmentVariable>();
        if (doc is not null)
            CollectEnvBlocks(doc, content, filePath, variables);

        var usages = new List<EnvironmentVariable>();

        // ${{ secrets.X }} / ${{ vars.X }} → usages.
        foreach (Match match in SecretRefRe.Matches(content))
        {
            var subkind = match.Groups[1].Value;
            var name = match.Groups[2].Value;
            var origin = new Origin
            {
                FilePath = filePath,
                Line = YamlInterp.LineForOffset(content, match.Index),
                Kind = OriginKind.Usage,
                Format = OriginFormat.GithubActions,
                Subkind = subkind == "vars" ? "vars" : "secrets",
            };
            usages.Add(EnvironmentVariable.Create(name, null, new List<Origin> { origin }));
        }

        // $VAR / ${VAR} → usages.
        foreach (var interp in YamlInterp.ScanInterpolations(content))
        {
            var origin = new Origin
            {
                FilePath = filePath,
                Line = interp.Line,
                Kind = OriginKind.Usage,
                Format = OriginFormat.GithubActions,
            };
            usages.Add(EnvironmentVariable.Create(interp.Name, null, new List<Origin> { origin }));
        }

        return new EnvironmentFile
        {
            FilePath = filePath,
            Format = FileFormat.GithubActions,
            Variables = EnvironmentVariable.Merge(variables),
            Usages = EnvironmentVariable.Merge(usages),
        };
    }

    /// Recursively collect every `env:` block as definition variables.
    private static void CollectEnvBlocks(object? node, string content, string filePath, List<EnvironmentVariable> output)
    {
        if (node is List<object?> list)
        {
            foreach (var item in list)
                CollectEnvBlocks(item, content, filePath, output);
            return;
        }
        if (node is not Dictionary<string, object?> obj)
            return;

        if (obj.TryGetValue("env", out var envObj) && envObj is Dictionary<string, object?> envMap)
        {
            foreach (var (key, rawValue) in envMap)
            {
                if (key.Length == 0)
                    continue;
                string? value = rawValue is null ? null : YamlFacade.JsString(rawValue);
                var origin = new Origin
                {
                    FilePath = filePath,
                    Line = LineForName(content, key),
                    Kind = value is null ? OriginKind.Reference : OriginKind.Definition,
                    Format = OriginFormat.GithubActions,
                };
                output.Add(EnvironmentVariable.Create(key, value, new List<Origin> { origin }));
            }
        }

        foreach (var value in obj.Values)
            CollectEnvBlocks(value, content, filePath, output);
    }

    /// Best-effort line lookup for an `env:` key in the raw YAML text.
    private static int? LineForName(string content, string name)
    {
        var escaped = Regex.Escape(name);
        var re = new Regex($@"^\s*[""']?{escaped}[""']?\s*:", RegexOptions.Multiline);
        var match = re.Match(content);
        return match.Success ? YamlInterp.LineForOffset(content, match.Index) : null;
    }
}
