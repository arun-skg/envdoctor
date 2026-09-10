using Envdoctor.Core;
using Envdoctor.Models;
using Envdoctor.Utils;

namespace Envdoctor.Formatters;

/// Render findings as SARIF 2.1.0 for GitHub code scanning.
public static class SarifFormatter
{
    private const string SarifSchema =
        "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json";

    /// Detectors whose default severity is `error`; everything else defaults
    /// to `warning`. Mirrors the reference `defaultLevelForDetector`.
    private static readonly string[] ErrorDetectors =
    {
        "missing",
        "undefined-in-source",
        "type-mismatch",
        "public-prefix",
    };

    public static string RenderSarif(IReadOnlyList<Finding> findings, string rootDir)
    {
        var results = findings.Select(f => FindingToSarif(f, rootDir)).ToList<object?>();

        return Json.Pretty(new JsonObject
        {
            { "$schema", SarifSchema },
            { "version", "2.1.0" },
            {
                "runs", new List<object?>
                {
                    new JsonObject
                    {
                        {
                            "tool", new JsonObject
                            {
                                {
                                    "driver", new JsonObject
                                    {
                                        { "name", "envdoctor" },
                                        { "informationUri", "https://github.com/arun-skg/envdoctor" },
                                        { "rules", RenderRules() },
                                    }
                                },
                            }
                        },
                        { "results", results },
                    },
                }
            },
        });
    }

    private static string SeverityToLevel(Severity severity) => severity switch
    {
        Severity.Error => "error",
        Severity.Warning => "warning",
        Severity.Info => "note",
        _ => "note",
    };

    private static object FindingToSarif(Finding f, string rootDir)
    {
        var locations = f.Locations.Select(o =>
        {
            var rel = Core.Discover.RelativeTo(rootDir, o.FilePath) ?? o.FilePath;
            var physical = new JsonObject
            {
                { "artifactLocation", new JsonObject { { "uri", rel.Replace('\\', '/') } } },
            };
            if (o.Line is { } line && line > 0)
                physical.Add("region", new JsonObject { { "startLine", line } });
            return (object)new JsonObject { { "physicalLocation", physical } };
        }).ToList();

        return new JsonObject
        {
            { "ruleId", f.RuleId },
            { "level", SeverityToLevel(f.Severity) },
            { "message", new JsonObject { { "text", $"{f.Variable}: {f.Message}" } } },
            { "locations", locations },
        };
    }

    /// The full detector catalog, matching the reference CLI (all rules
    /// appear, not only the ones with findings).
    private static List<object> RenderRules() =>
        Audit.AllDetectors()
            .Select(d =>
            {
                var level = ErrorDetectors.Contains(d.Id) ? "error" : "warning";
                return (object)new JsonObject
                {
                    { "id", d.Id },
                    { "name", d.Name },
                    { "shortDescription", new JsonObject { { "text", d.Description } } },
                    { "defaultConfiguration", new JsonObject { { "level", level } } },
                };
            })
            .ToList();
}
