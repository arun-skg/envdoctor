using Envdoctor.Config;
using Envdoctor.Detectors;
using Envdoctor.Models;

namespace Envdoctor.Core;

public static class Pipeline
{
    /// Load a project: discover files, assemble the model, and return it
    /// together with the config used.
    public static (ProjectModel Model, EnvdoctorConfig Config) LoadProject(string rootDir) =>
        LoadProjectFiltered(rootDir, null);

    /// Like <see cref="LoadProject"/>, but restricts the assembled model to
    /// `changed` files when a set is provided (used by `scan --staged` /
    /// `--since`).
    public static (ProjectModel Model, EnvdoctorConfig Config) LoadProjectFiltered(
        string rootDir,
        HashSet<string>? changed)
    {
        var config = ConfigLoader.LoadConfigOrDefault(rootDir);

        var envFiles = Discover.DiscoverFiles(rootDir, config);
        var sourceFiles = Discover.DiscoverSourceFiles(rootDir, config);

        var allPaths = new List<string>(envFiles);
        allPaths.AddRange(sourceFiles);

        if (changed is not null)
            allPaths = allPaths.Where(changed.Contains).ToList();

        var model = ModelAssembler.AssembleModel(rootDir, config, allPaths);
        return (model, config);
    }

    /// Run a complete audit: load project, build index, run detectors.
    public static List<Finding> AuditProject(string rootDir)
    {
        var (model, config) = LoadProject(rootDir);
        var index = IndexedModel.BuildIndex(model);
        return Audit.RunAudit(model, config, index);
    }

    /// Build a summary from a list of findings and the scanned project model.
    public static AuditSummary Summarize(ProjectModel model, IReadOnlyList<Finding> findings)
    {
        var errors = 0;
        var warnings = 0;
        var infos = 0;
        foreach (var f in findings)
        {
            switch (f.Severity)
            {
                case Severity.Error: errors++; break;
                case Severity.Warning: warnings++; break;
                case Severity.Info: infos++; break;
            }
        }
        return new AuditSummary
        {
            FilesScanned = model.AllFiles.Count,
            VariablesFound = DistinctVariableCount(model),
            Errors = errors,
            Warnings = warnings,
            Infos = infos,
            Total = errors + warnings + infos,
        };
    }

    /// Count distinct variable names across every scanned file (definitions
    /// and usages).
    private static int DistinctVariableCount(ProjectModel model)
    {
        var names = new HashSet<string>();
        foreach (var file in model.AllFiles)
        {
            foreach (var v in file.Variables)
                names.Add(v.Name);
            foreach (var v in file.Usages)
                names.Add(v.Name);
        }
        return names.Count;
    }
}
