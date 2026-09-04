using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Parsers;

/// Parser for docker-compose files.
///
/// Definitions come from `services.<name>.environment:` blocks (both the map
/// and the list form). Bare list entries (`- FOO`) become value-less
/// definitions. `$VAR` / `${VAR}` interpolation anywhere in the file becomes
/// usages.
public sealed class DockerComposeParser : IParser
{
    private static readonly HashSet<string> ComposeBasenames = new()
    {
        "docker-compose.yml",
        "docker-compose.yaml",
        "docker-compose.override.yml",
        "docker-compose.override.yaml",
        "compose.yml",
        "compose.yaml",
    };

    public string Id => "docker-compose";

    public bool MatchPath(string filePath) => ComposeBasenames.Contains(Path.GetFileName(filePath));

    public EnvironmentFile Parse(string content, string filePath)
    {
        var doc = YamlFacade.LoadFirst(content);
        var variables = new List<EnvironmentVariable>();

        if (doc is Dictionary<string, object?> root &&
            root.TryGetValue("services", out var servicesObj) &&
            servicesObj is Dictionary<string, object?> services)
        {
            foreach (var (_, serviceValue) in services)
            {
                object? env = null;
                if (serviceValue is Dictionary<string, object?> svc)
                    svc.TryGetValue("environment", out env);

                foreach (var entry in NormalizeEnvironment(env, content, filePath))
                    variables.Add(entry);
            }
        }

        // `$VAR` / `${VAR}` interpolation → usages.
        var usages = new List<EnvironmentVariable>();
        foreach (var interp in YamlInterp.ScanInterpolations(content))
        {
            var origin = new Origin
            {
                FilePath = filePath,
                Line = interp.Line,
                Kind = OriginKind.Usage,
                Format = OriginFormat.DockerCompose,
            };
            usages.Add(EnvironmentVariable.Create(interp.Name, null, new List<Origin> { origin }));
        }

        return new EnvironmentFile
        {
            FilePath = filePath,
            Format = FileFormat.DockerCompose,
            Variables = EnvironmentVariable.Merge(variables),
            Usages = EnvironmentVariable.Merge(usages),
        };
    }

    /// Flatten a service's `environment:` value into definition variables.
    private static List<EnvironmentVariable> NormalizeEnvironment(object? env, string content, string filePath)
    {
        var variables = new List<EnvironmentVariable>();
        if (env is null)
            return variables;

        if (env is Dictionary<string, object?> map)
        {
            // Map form: KEY: value
            foreach (var (key, rawValue) in map)
            {
                string? value = rawValue is null ? null : YamlFacade.JsString(rawValue);
                var origin = new Origin
                {
                    FilePath = filePath,
                    Line = LineForName(content, key),
                    Kind = value is null ? OriginKind.Reference : OriginKind.Definition,
                    Format = OriginFormat.DockerCompose,
                };
                variables.Add(EnvironmentVariable.Create(key, value, new List<Origin> { origin }));
            }
        }
        else if (env is List<object?> list)
        {
            // List form: - KEY=value | - KEY
            foreach (var item in list)
            {
                if (item is not string s)
                    continue;
                var trimmed = s.Trim();
                if (trimmed.Length == 0)
                    continue;
                var eq = trimmed.IndexOf('=');
                string key;
                string? value;
                if (eq < 0)
                {
                    key = trimmed;
                    value = null;
                }
                else
                {
                    key = trimmed[..eq];
                    value = trimmed[(eq + 1)..];
                }
                var origin = new Origin
                {
                    FilePath = filePath,
                    Line = LineForName(content, key),
                    Kind = value is null ? OriginKind.Reference : OriginKind.Definition,
                    Format = OriginFormat.DockerCompose,
                };
                variables.Add(EnvironmentVariable.Create(key, value, new List<Origin> { origin }));
            }
        }

        return variables;
    }

    /// Best-effort line lookup for a definition name in the raw YAML text.
    private static int? LineForName(string content, string name)
    {
        var escaped = Regex.Escape(name);
        // Supports both map form (`KEY: value`) and list form (`- KEY=value`).
        var re = new Regex($@"^\s*[- ]*[""']?{escaped}[""']?\s*[:=]", RegexOptions.Multiline);
        var match = re.Match(content);
        return match.Success ? YamlInterp.LineForOffset(content, match.Index) : null;
    }
}
