using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Missing: a variable that is referenced (in docker-compose, GitHub Actions,
/// or `.env.example`) but defined in no environment file. Source-code
/// references are the concern of the `undefined-in-source` detector.
public sealed class MissingDetector : IDetector
{
    public string Id => "missing";
    public string Name => "missing";
    public string Description =>
        "Referenced in docker-compose, GitHub Actions, or .env.example but not defined in any environment file.";

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();
        var defined = index.EnvDefinitions.Keys.ToHashSet();
        var sourceUsed = index.SourceUsages.Keys.ToHashSet();
        var seen = new HashSet<string>();

        // Built in the same three phases as the reference CLI (compose defs,
        // then .env.example names, then compose `${VAR}` interpolations) so the
        // emission order matches.
        var referenced = new List<(string Name, List<Origin> Origins)>();

        // Compose definitions that are NOT in any .env file are "missing".
        var composeEntries = index.ComposeDefinitions
            .OrderBy(kv => DefSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);
        foreach (var (name, defs) in composeEntries)
        {
            if (!defined.Contains(name) && !sourceUsed.Contains(name))
                referenced.Add((name, defs.Select(d => d.Origin.Clone()).ToList()));
        }

        // .env.example names that are NOT in any .env file are "missing".
        foreach (var file in index.Model.EnvFiles)
        {
            if (file.Environment != "example")
                continue;
            foreach (var v in file.Variables)
            {
                if (!defined.Contains(v.Name) && !sourceUsed.Contains(v.Name))
                    referenced.Add((v.Name, new List<Origin>()));
            }
        }

        // `${VAR}` interpolation in docker-compose means compose expects the
        // variable to exist. GitHub Actions `secrets.X`/`vars.X` references are
        // intentionally NOT checked here.
        var usageEntries = index.Usages
            .OrderBy(kv => OriginSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);
        foreach (var (name, origins) in usageEntries)
        {
            var composeOrigins = origins
                .Where(o => o.Format == OriginFormat.DockerCompose)
                .Select(o => o.Clone())
                .ToList();
            if (composeOrigins.Count == 0)
                continue;
            if (defined.Contains(name) || sourceUsed.Contains(name))
                continue;
            referenced.Add((name, composeOrigins));
        }

        foreach (var (name, origins) in referenced)
        {
            if (seen.Add(name))
            {
                findings.Add(MakeFinding(
                    "missing",
                    Severity.Error,
                    name,
                    "referenced but not defined in any environment file",
                    origins));
            }
        }

        return findings;
    }
}
