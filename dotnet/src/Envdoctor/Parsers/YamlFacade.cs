using System.Globalization;
using System.Text.RegularExpressions;
using YamlDotNet.RepresentationModel;

namespace Envdoctor.Parsers;

/// Helpers over YamlDotNet that reproduce the scalar-resolution semantics of
/// the reference's `yaml` npm package (YAML 1.2 core schema): plain scalars
/// become null/bool/int/float/string; quoted scalars are always strings.
public static class YamlFacade
{
    private static readonly Regex IntRe = new(@"^[-+]?[0-9]+$", RegexOptions.Compiled);
    private static readonly Regex HexIntRe = new(@"^0x[0-9a-fA-F]+$", RegexOptions.Compiled);
    private static readonly Regex OctIntRe = new(@"^0o[0-7]+$", RegexOptions.Compiled);
    private static readonly Regex FloatRe = new(
        @"^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$", RegexOptions.Compiled);

    /// Parse all documents; returns an empty list when the content is not
    /// parseable YAML (the callers still scan raw text for interpolations).
    public static List<object?> LoadAll(string content)
    {
        try
        {
            var stream = new YamlStream();
            stream.Load(new StringReader(content));
            return stream.Documents.Select(d => ToPlain(d.RootNode)).ToList();
        }
        catch (YamlDotNet.Core.YamlException)
        {
            return new List<object?>();
        }
    }

    /// Parse the first document; null when unparseable.
    public static object? LoadFirst(string content)
    {
        var docs = LoadAll(content);
        return docs.Count > 0 ? docs[0] : null;
    }

    public static object? ToPlain(YamlNode node) => node switch
    {
        YamlScalarNode scalar => ResolveScalar(scalar),
        YamlSequenceNode seq => seq.Children.Select(ToPlain).ToList(),
        YamlMappingNode map => map.Children.ToDictionary(
            kv => JsString(ToPlain(kv.Key)),
            kv => ToPlain(kv.Value)),
        _ => null,
    };

    private static object? ResolveScalar(YamlScalarNode scalar)
    {
        if (scalar.Style != YamlDotNet.Core.ScalarStyle.Plain)
            return scalar.Value ?? "";
        var s = scalar.Value ?? "";
        if (s.Length == 0 || s is "~" or "null" or "Null" or "NULL")
            return null;
        if (s is "true" or "True" or "TRUE")
            return true;
        if (s is "false" or "False" or "FALSE")
            return false;
        if (IntRe.IsMatch(s) && long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var l))
            return l;
        if (HexIntRe.IsMatch(s) && long.TryParse(s[2..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var hex))
            return hex;
        if (OctIntRe.IsMatch(s))
        {
            try { return Convert.ToInt64(s[2..], 8); }
            catch (OverflowException) { }
        }
        if ((s.Contains('.') || s.Contains('e') || s.Contains('E')) &&
            FloatRe.IsMatch(s) &&
            double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d))
            return d;
        return s;
    }

    /// JS `String(value)` for the scalar shapes YAML resolution produces.
    public static string JsString(object? value) => value switch
    {
        null => "null",
        string s => s,
        bool b => b ? "true" : "false",
        long l => l.ToString(CultureInfo.InvariantCulture),
        double d => JsNumber(d),
        List<object?> => string.Join(",", ((List<object?>)value).Select(JsString)),
        Dictionary<string, object?> => "[object Object]",
        _ => value.ToString() ?? "",
    };

    /// JS number-to-string: shortest round-trip, lowercase `e` exponent without
    /// leading zeros, matching `Number.prototype.toString`.
    private static string JsNumber(double d)
    {
        var s = d.ToString(CultureInfo.InvariantCulture);
        var e = s.IndexOf('E');
        if (e < 0)
            return s;
        var mantissa = s[..e];
        var exp = s[(e + 1)..];
        var neg = exp.StartsWith('-');
        var digits = exp.TrimStart('-', '+').TrimStart('0');
        if (digits.Length == 0)
            digits = "0";
        return $"{mantissa}e{(neg ? "-" : "+")}{digits}";
    }
}
