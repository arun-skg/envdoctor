using Envdoctor.Config;
using Envdoctor.Models;
using Envdoctor.Parsers;
using Envdoctor.Utils;

namespace Envdoctor.Core;

/// Assemble a `ProjectModel` from discovered file paths.
public static class ModelAssembler
{
    public static ProjectModel AssembleModel(string rootDir, EnvdoctorConfig config, IReadOnlyList<string> discovered)
    {
        var registry = ParserRegistry.DefaultRegistry(config.SourceExtensions);
        var envFiles = new List<EnvironmentFile>();
        var composeFiles = new List<EnvironmentFile>();
        var actionFiles = new List<EnvironmentFile>();
        var k8sFiles = new List<EnvironmentFile>();
        var sourceFiles = new List<EnvironmentFile>();
        var allFiles = new List<EnvironmentFile>();
        var parseErrors = new List<ParseError>();

        foreach (var path in discovered)
        {
            string content;
            try
            {
                content = File.ReadAllText(path);
            }
            catch (Exception e)
            {
                parseErrors.Add(new ParseError { FilePath = path, Error = $"Cannot read file: {e.Message}" });
                continue;
            }

            // Skip if ignored by config
            if (config.IgnoreFiles.Count > 0)
            {
                var rel = Discover.RelativeTo(rootDir, path);
                if (rel is not null && Glob.MatchesAnyGlob(config.IgnoreFiles, rel))
                    continue;
            }

            EnvironmentFile? parsed = null;
            foreach (var parser in registry)
            {
                if (parser.MatchPath(path))
                {
                    parsed = parser.Parse(content, path);
                    break;
                }
            }

            if (parsed is not null)
            {
                switch (parsed.Format)
                {
                    case FileFormat.Dotenv: envFiles.Add(parsed); break;
                    case FileFormat.DockerCompose: composeFiles.Add(parsed); break;
                    case FileFormat.GithubActions: actionFiles.Add(parsed); break;
                    case FileFormat.Kubernetes: k8sFiles.Add(parsed); break;
                    case FileFormat.Source: sourceFiles.Add(parsed); break;
                }
                allFiles.Add(parsed);
            }
        }

        // Apply ignoreVariables to parsed variables
        envFiles = ApplyIgnoreVariables(envFiles, config);
        composeFiles = ApplyIgnoreVariables(composeFiles, config);
        actionFiles = ApplyIgnoreVariables(actionFiles, config);
        k8sFiles = ApplyIgnoreVariables(k8sFiles, config);
        sourceFiles = ApplyIgnoreVariables(sourceFiles, config);

        // Apply environment overrides if configured
        envFiles = ApplyEnvironmentOverrides(envFiles, config);

        return new ProjectModel
        {
            RootDir = rootDir,
            Config = config,
            EnvFiles = envFiles,
            ComposeFiles = composeFiles,
            ActionFiles = actionFiles,
            K8sFiles = k8sFiles,
            SourceFiles = sourceFiles,
            AllFiles = allFiles,
            ParseErrors = parseErrors,
        };
    }

    /// Remove variables whose names match `ignoreVariables` globs.
    private static List<EnvironmentFile> ApplyIgnoreVariables(List<EnvironmentFile> files, EnvdoctorConfig config)
    {
        if (config.IgnoreVariables.Count == 0)
            return files;
        foreach (var f in files)
        {
            f.Variables.RemoveAll(v => Glob.MatchesAnyGlob(config.IgnoreVariables, v.Name));
            f.Usages.RemoveAll(v => Glob.MatchesAnyGlob(config.IgnoreVariables, v.Name));
        }
        return files;
    }

    /// If `environments` is configured, override the environment label for
    /// files matching the given globs.
    private static List<EnvironmentFile> ApplyEnvironmentOverrides(List<EnvironmentFile> files, EnvdoctorConfig config)
    {
        if (config.Environments is null)
            return files;
        foreach (var f in files)
        {
            var rel = f.FilePath;
            foreach (var (envLabel, globs) in config.Environments)
            {
                if (Glob.MatchesAnyGlob(globs, rel))
                {
                    f.Environment = envLabel;
                    break;
                }
            }
        }
        return files;
    }
}
