using Envdoctor.Models;
using Envdoctor.Utils;

namespace Envdoctor.Formatters;

public static class JsonFormatter
{
    /// Render a complete AuditResult as JSON (internal snake_case model shape).
    public static string RenderAuditResultJson(AuditResult result)
    {
        var findings = result.Findings.Select(f =>
        {
            var locations = f.Locations.Select(o =>
            {
                var loc = new JsonObject { { "file_path", o.FilePath } };
                if (o.Line is { } line)
                    loc.Add("line", line);
                loc.Add("kind", o.Kind.AsStr());
                if (o.Environment is not null)
                    loc.Add("environment", o.Environment);
                if (o.Format is { } format)
                    loc.Add("format", format.AsStr());
                if (o.Subkind is not null)
                    loc.Add("subkind", o.Subkind);
                return (object)loc;
            }).ToList();
            return (object)new JsonObject
            {
                { "id", f.Id },
                { "rule_id", f.RuleId },
                { "severity", f.Severity.AsStr() },
                { "variable", f.Variable },
                { "message", f.Message },
                { "locations", locations },
            };
        }).ToList();

        return Json.Pretty(new JsonObject
        {
            { "findings", findings },
            {
                "summary", new JsonObject
                {
                    { "files_scanned", result.Summary.FilesScanned },
                    { "variables_found", result.Summary.VariablesFound },
                    { "errors", result.Summary.Errors },
                    { "warnings", result.Summary.Warnings },
                    { "infos", result.Summary.Infos },
                    { "total", result.Summary.Total },
                }
            },
            { "exit_code", result.ExitCode },
        });
    }
}
