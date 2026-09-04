using Envdoctor.Models;

namespace Envdoctor.Parsers;

/// Parser for Kubernetes manifests.
///
/// Matches YAML files that look like Kubernetes resources (have apiVersion and
/// kind). Extracts container environment definitions and `${VAR}` / `$VAR`
/// interpolations from command/args/env values.
public sealed class K8sParser : IParser
{
    public string Id => "kubernetes";

    public bool MatchPath(string filePath)
    {
        var ext = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
        return ext is "yaml" or "yml";
    }

    public EnvironmentFile Parse(string content, string filePath)
    {
        var docArray = YamlFacade.LoadAll(content);

        var variables = new List<EnvironmentVariable>();
        var usages = new List<EnvironmentVariable>();

        foreach (var doc in docArray)
        {
            if (!LooksLikeK8s(doc))
                continue;
            WalkResource((Dictionary<string, object?>)doc!, filePath, variables, usages);
        }

        return new EnvironmentFile
        {
            FilePath = filePath,
            Format = FileFormat.Kubernetes,
            Variables = EnvironmentVariable.Merge(variables),
            Usages = EnvironmentVariable.Merge(usages),
        };
    }

    private static bool LooksLikeK8s(object? doc) =>
        doc is Dictionary<string, object?> obj &&
        obj.TryGetValue("apiVersion", out var apiVersion) && apiVersion is string &&
        obj.TryGetValue("kind", out var kind) && kind is string;

    private static Origin OriginAt(string filePath, int? line, OriginKind kind = OriginKind.Definition) =>
        new()
        {
            FilePath = filePath,
            Line = line,
            Kind = kind,
            Format = OriginFormat.Kubernetes,
        };

    private static void WalkResource(
        Dictionary<string, object?> doc,
        string filePath,
        List<EnvironmentVariable> variables,
        List<EnvironmentVariable> usages)
    {
        var kind = doc.TryGetValue("kind", out var k) ? k as string : null;

        // ConfigMap data keys become definitions.
        if (kind == "ConfigMap")
        {
            if (GetObject(doc, "data") is { } data)
            {
                foreach (var (key, value) in data)
                {
                    if (value is not string valueStr || key.Length == 0)
                        continue;
                    variables.Add(EnvironmentVariable.Create(
                        key, valueStr, new List<Origin> { OriginAt(filePath, null) }));
                }
            }
            return;
        }

        var spec = GetObject(doc, "spec");
        if (spec is null)
            return;

        var template = GetObject(spec, "template");
        var podSpec = template is not null ? GetObject(template, "spec") : spec;
        if (podSpec is null)
            return;

        var containers = (GetArray(podSpec, "containers") ?? new List<object?>())
            .Concat(GetArray(podSpec, "initContainers") ?? new List<object?>());

        foreach (var container in containers)
        {
            if (container is not Dictionary<string, object?> containerObj)
                continue;

            foreach (var raw in GetArray(containerObj, "env") ?? new List<object?>())
            {
                if (raw is not Dictionary<string, object?> entry)
                    continue;
                if (entry.TryGetValue("name", out var nameObj) && nameObj is string name && name.Length > 0)
                {
                    if (entry.TryGetValue("value", out var value) && value is string valueStr)
                    {
                        variables.Add(EnvironmentVariable.Create(
                            name, valueStr, new List<Origin> { OriginAt(filePath, null) }));
                    }
                    else if (entry.ContainsKey("valueFrom"))
                    {
                        // Referenced but value provided elsewhere (ConfigMap/Secret).
                        usages.Add(EnvironmentVariable.Create(
                            name, null, new List<Origin> { OriginAt(filePath, null, OriginKind.Usage) }));
                    }
                }
            }

            foreach (var raw in GetArray(containerObj, "envFrom") ?? new List<object?>())
            {
                if (raw is not Dictionary<string, object?> entry)
                    continue;
                var prefix = entry.TryGetValue("prefix", out var p) && p is string ps ? ps : "";
                if (GetObject(entry, "configMapRef") is { } configMapRef &&
                    configMapRef.TryGetValue("name", out var cmName) && cmName is string)
                {
                    usages.Add(EnvironmentVariable.Create(
                        $"{prefix}*", null, new List<Origin> { OriginAt(filePath, null, OriginKind.Usage) }));
                }
                if (GetObject(entry, "secretRef") is { } secretRef &&
                    secretRef.TryGetValue("name", out var secName) && secName is string)
                {
                    usages.Add(EnvironmentVariable.Create(
                        $"{prefix}*", null, new List<Origin> { OriginAt(filePath, null, OriginKind.Usage) }));
                }
            }

            // Interpolations in command/args.
            foreach (var key in new[] { "command", "args" })
            {
                var list = GetArray(containerObj, key);
                if (list is null)
                    continue;
                foreach (var item in list)
                {
                    if (item is not string itemStr)
                        continue;
                    foreach (var interp in YamlInterp.ScanInterpolations(itemStr))
                    {
                        usages.Add(EnvironmentVariable.Create(
                            interp.Name, null,
                            new List<Origin> { OriginAt(filePath, interp.Line, OriginKind.Usage) }));
                    }
                }
            }
        }
    }

    private static Dictionary<string, object?>? GetObject(Dictionary<string, object?> obj, string key) =>
        obj.TryGetValue(key, out var value) && value is Dictionary<string, object?> map ? map : null;

    private static List<object?>? GetArray(Dictionary<string, object?> obj, string key) =>
        obj.TryGetValue(key, out var value) && value is List<object?> list ? list : null;
}
