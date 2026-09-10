using Envdoctor.Config;
using Envdoctor.Detectors;
using Envdoctor.Models;
using Envdoctor.Utils;

namespace Envdoctor.Core;

public static class Audit
{
    /// Detector ids in a well-known order. The order here is the order
    /// findings are produced.
    public static List<IDetector> AllDetectors() =>
        new()
        {
            new MissingDetector(),
            new UnusedDetector(),
            new UndefinedSourceDetector(),
            new DuplicatesDetector(),
            new EnvironmentDiffDetector(),
            new TypeMismatchDetector(),
            new PublicPrefixDetector(),
            new WeakSecretDetector(),
            new TypoDetector(),
            new SchemaValidationDetector(),
        };

    /// Run the full audit pipeline over a model and return aggregated findings.
    public static List<Finding> RunAudit(ProjectModel model, EnvdoctorConfig config, IndexedModel index)
    {
        var findings = new List<Finding>();
        foreach (var detector in AllDetectors())
            findings.AddRange(detector.Detect(index));

        findings = ApplyRuleSeverities(findings, config);
        findings = ApplyIgnores(findings, config);

        return findings;
    }

    /// Apply user-configured severity overrides for each rule. "off" removes
    /// the finding entirely, "error"/"warning" rewrite its severity.
    private static List<Finding> ApplyRuleSeverities(List<Finding> findings, EnvdoctorConfig config)
    {
        var result = new List<Finding>();
        foreach (var f in findings)
        {
            if (!config.Rules.TryGetValue(f.RuleId, out var overrideSev))
            {
                result.Add(f);
                continue;
            }
            switch (overrideSev)
            {
                case RuleSeverity.Off:
                    break;
                case RuleSeverity.Error:
                    var ef = f.Clone();
                    ef.Severity = Severity.Error;
                    result.Add(ef);
                    break;
                case RuleSeverity.Warning:
                    var wf = f.Clone();
                    wf.Severity = Severity.Warning;
                    result.Add(wf);
                    break;
            }
        }
        return result;
    }

    /// Drop findings whose variable matches any `ignoreVariables` glob.
    private static List<Finding> ApplyIgnores(List<Finding> findings, EnvdoctorConfig config)
    {
        if (config.IgnoreVariables.Count == 0)
            return findings;
        return findings.Where(f => !Glob.MatchesAnyGlob(config.IgnoreVariables, f.Variable)).ToList();
    }
}
