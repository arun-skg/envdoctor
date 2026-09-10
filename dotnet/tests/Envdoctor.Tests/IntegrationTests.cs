using Envdoctor.Commands;
using Envdoctor.Core;
using Envdoctor.Models;
using Envdoctor.Runtime;
using Envdoctor.Utils;
using Xunit;

namespace Envdoctor.Tests;

public sealed class TempProject : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(
        System.IO.Path.GetTempPath(), "envdoctor-test-" + Guid.NewGuid().ToString("N"));

    public TempProject() => Directory.CreateDirectory(Path);

    public void Write(string rel, string content) =>
        File.WriteAllText(System.IO.Path.Combine(Path, rel), content);

    public string Read(string rel) => File.ReadAllText(System.IO.Path.Combine(Path, rel));

    public bool Exists(string rel) => File.Exists(System.IO.Path.Combine(Path, rel));

    public void Dispose()
    {
        try
        {
            Directory.Delete(Path, recursive: true);
        }
        catch
        {
            // Best-effort cleanup.
        }
    }
}

public class IntegrationTests
{
    private static void CreateTestProject(TempProject dir)
    {
        dir.Write(".env",
            "DATABASE_URL=postgres://localhost:5432/myapp\nAPI_KEY=secret123\nDEBUG=true\nPORT=3000\n");
        dir.Write(".env.example", "DATABASE_URL=\nAPI_KEY=\nDEBUG=false\nPORT=\n");
        dir.Write("config.js",
            "const db = process.env.DATABASE_URL;\nconst port = process.env.PORT;\nconst missing = process.env.MISSING_SECRET;\n");
        dir.Write("docker-compose.yml",
            "version: '3'\nservices:\n  app:\n    environment:\n      - DATABASE_URL\n      - API_KEY\n      - DEBUG\n");
    }

    private static ScanArgs Scan(TempProject dir, OutputFormat format = OutputFormat.Human) =>
        new()
        {
            Root = dir.Path,
            Output = new OutputArgs { Format = format },
        };

    [Fact]
    public void ScanFindsIssues()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);
        Assert.Equal(1, ScanCommand.Run(Scan(temp)));
    }

    [Fact]
    public void InitCreatesConfig()
    {
        using var temp = new TempProject();
        var exit = InitCommand.Run(new InitArgs { Root = temp.Path, Force = true });
        Assert.Equal(0, exit);
        Assert.True(temp.Exists("envdoctor.config.toml"));
        var content = temp.Read("envdoctor.config.toml");
        Assert.Contains("ignoreVariables", content);
        Assert.Contains("rules", content);
    }

    [Fact]
    public void GenerateEnvExample()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);
        var exit = GenerateCommand.Run(new GenerateArgs
        {
            Target = GenerateTarget.EnvExample,
            Root = temp.Path,
        });
        Assert.Equal(0, exit);
        var content = temp.Read(".env.example");
        Assert.Contains("DATABASE_URL", content);
        Assert.Contains("API_KEY", content);
    }

    [Fact]
    public void GenerateEnvDoc()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);
        Assert.Equal(0, GenerateCommand.Run(new GenerateArgs
        {
            Target = GenerateTarget.EnvDoc,
            Root = temp.Path,
        }));
    }

    [Fact]
    public void GenerateEnvTypes()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);
        Assert.Equal(0, GenerateCommand.Run(new GenerateArgs
        {
            Target = GenerateTarget.EnvTypes,
            Root = temp.Path,
        }));
    }

    [Fact]
    public void GenerateConfigSchema()
    {
        using var temp = new TempProject();
        Assert.Equal(0, GenerateCommand.Run(new GenerateArgs
        {
            Target = GenerateTarget.ConfigSchema,
            Root = temp.Path,
        }));
    }

    [Fact]
    public void GenerateConfigTemplate()
    {
        using var temp = new TempProject();
        Assert.Equal(0, GenerateCommand.Run(new GenerateArgs
        {
            Target = GenerateTarget.ConfigTemplate,
            Root = temp.Path,
        }));
    }

    [Fact]
    public void GenerateGithubActions()
    {
        using var temp = new TempProject();
        Assert.Equal(0, GenerateCommand.Run(new GenerateArgs
        {
            Target = GenerateTarget.GithubActions,
            Root = temp.Path,
        }));
    }

    [Fact]
    public void ScanJsonOutput()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);
        Assert.Equal(1, ScanCommand.Run(Scan(temp, OutputFormat.Json)));
    }

    [Fact]
    public void ScanSarifOutput()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);
        Assert.Equal(1, ScanCommand.Run(Scan(temp, OutputFormat.Sarif)));
    }

    [Fact]
    public void ScanWithConfig()
    {
        using var temp = new TempProject();
        CreateTestProject(temp);

        var baseline = ScanCommand.Run(Scan(temp));
        Assert.Equal(1, baseline);

        temp.Write("envdoctor.config.toml", "ignoreVariables = [\"MISSING_SECRET\"]\n");
        var exit = ScanCommand.Run(Scan(temp));
        Assert.Equal(0, exit);
    }

    [Fact]
    public void DiffReportsMissingKeys()
    {
        using var temp = new TempProject();
        temp.Write(".env", "DATABASE_URL=postgres://localhost/dev\nDEBUG=true\n");
        temp.Write(".env.production", "DATABASE_URL=postgres://prod/db\n");

        var exit = DiffCommand.Run(new DiffArgs
        {
            Root = temp.Path,
            EnvA = "development",
            EnvB = "production",
        });
        Assert.Equal(1, exit);

        var exitJson = DiffCommand.Run(new DiffArgs
        {
            Root = temp.Path,
            EnvA = "development",
            EnvB = "production",
            Json = true,
        });
        Assert.Equal(1, exitJson);
    }

    [Fact]
    public void SyncDryRunDoesNotModifyTarget()
    {
        using var temp = new TempProject();
        temp.Write(".env", "DATABASE_URL=postgres://localhost/dev\nDEBUG=true\nEXTRA_KEY=value\n");
        temp.Write(".env.production", "DATABASE_URL=postgres://prod/db\n");
        var before = temp.Read(".env.production");

        var exit = SyncCommand.Run(new SyncArgs
        {
            Root = temp.Path,
            From = "development",
            To = "production",
            DryRun = true,
        });
        Assert.Equal(0, exit);
        Assert.Equal(before, temp.Read(".env.production"));
    }

    [Fact]
    public void SnapshotDiffIdenticalAndDiffering()
    {
        using var temp = new TempProject();
        var snapshot = Capture.CaptureSnapshot(false);
        var json = Token.SnapshotToJson(snapshot);

        temp.Write("a.json", json);
        temp.Write("b.json", json);

        var exitSame = SnapshotDiffCommand.Run(new SnapshotDiffArgs
        {
            Root = temp.Path,
            A = "a.json",
            B = "b.json",
        });
        Assert.Equal(0, exitSame);

        snapshot.Tools.Add(new ToolInfo
        {
            Tool = "zzz-fake-tool",
            Version = "9.9.9",
            ResolvedFrom = "PATH",
        });
        temp.Write("b.json", Token.SnapshotToJson(snapshot));

        var exitDiff = SnapshotDiffCommand.Run(new SnapshotDiffArgs
        {
            Root = temp.Path,
            A = "a.json",
            B = "b.json",
            Json = true,
        });
        Assert.Equal(1, exitDiff);
    }

    [Fact]
    public void GlobMatching()
    {
        Assert.True(Glob.MatchesGlob("AWS_*", "AWS_SECRET"));
        Assert.False(Glob.MatchesGlob("AWS_*", "GCP_SECRET"));
        Assert.True(Glob.MatchesGlob("FOO*", "FOO"));
        Assert.True(Glob.MatchesGlob("FOO*", "FOOBAR"));
        Assert.False(Glob.MatchesGlob("FOO*", "BAR"));

        Assert.True(Glob.MatchesAnyGlob(new[] { "AWS_*", "GCP_*" }, "AWS_KEY"));
        Assert.True(Glob.MatchesAnyGlob(new[] { "AWS_*", "GCP_*" }, "GCP_KEY"));
        Assert.False(Glob.MatchesAnyGlob(new[] { "AWS_*", "GCP_*" }, "AZURE_KEY"));
    }

    [Fact]
    public void VariableTypeInference()
    {
        Assert.Equal(VariableType.Integer, TypeInfer.InferType("42"));
        Assert.Equal(VariableType.Float, TypeInfer.InferType("3.14"));
        Assert.Equal(VariableType.Boolean, TypeInfer.InferType("true"));
        Assert.Equal(VariableType.Boolean, TypeInfer.InferType("false"));
        Assert.Equal(VariableType.Url, TypeInfer.InferType("https://example.com"));
        Assert.Equal(VariableType.Url, TypeInfer.InferType("http://localhost:3000"));
        Assert.Equal(VariableType.Json, TypeInfer.InferType("{\"key\": \"value\"}"));
        Assert.Equal(VariableType.String, TypeInfer.InferType("hello"));
        Assert.Equal(VariableType.Unknown, TypeInfer.InferType(null));
    }

    [Fact]
    public void SecretDetection()
    {
        Assert.True(EnvironmentVariable.IsSecretName("API_KEY"));
        Assert.True(EnvironmentVariable.IsSecretName("SECRET"));
        Assert.True(EnvironmentVariable.IsSecretName("PASSWORD"));
        Assert.True(EnvironmentVariable.IsSecretName("TOKEN"));
        Assert.True(EnvironmentVariable.IsSecretName("PRIVATE_KEY"));
        Assert.False(EnvironmentVariable.IsSecretName("DEBUG"));
        Assert.False(EnvironmentVariable.IsSecretName("PORT"));
        Assert.False(EnvironmentVariable.IsSecretName("NODE_ENV"));
    }
}
