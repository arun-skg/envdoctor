using System.Text.Json;
using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Utils;

public static class TypeInfer
{
    private static readonly Regex IntegerRe = new(@"^-?[0-9]+$", RegexOptions.Compiled);
    private static readonly Regex FloatRe = new(@"^-?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?$", RegexOptions.Compiled);
    private static readonly Regex BooleanRe = new(@"^(true|false|TRUE|FALSE)$", RegexOptions.Compiled);
    private static readonly Regex UrlRe = new(@"^https?://\S+$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// Infer the basic type of a variable value. Ordering matters: a value like
    /// "1" is an integer, "1.5" is a float, "true" is a boolean, and a URL wins
    /// over generic string. Anything unparseable or empty is "string" or "unknown".
    public static VariableType InferType(string? value)
    {
        if (value is null)
            return VariableType.Unknown;
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
            return VariableType.Unknown;
        if (IntegerRe.IsMatch(trimmed))
            return VariableType.Integer;
        if (FloatRe.IsMatch(trimmed))
            return VariableType.Float;
        if (BooleanRe.IsMatch(trimmed))
            return VariableType.Boolean;
        if (UrlRe.IsMatch(trimmed))
            return VariableType.Url;
        if (trimmed.StartsWith('{') || trimmed.StartsWith('['))
        {
            try
            {
                JsonDocument.Parse(trimmed);
                return VariableType.Json;
            }
            catch (JsonException)
            {
                // fall through to string
            }
        }
        return VariableType.String;
    }
}
