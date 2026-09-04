using System.Globalization;
using System.Text;

namespace Envdoctor.Utils;

/// An insertion-ordered JSON object.
public sealed class JsonObject : List<KeyValuePair<string, object?>>
{
    public void Add(string key, object? value) => Add(new KeyValuePair<string, object?>(key, value));
}

/// A minimal JSON writer producing the exact byte shape shared by
/// `JSON.stringify(x, null, 2)` and `serde_json::to_string_pretty`: two-space
/// indentation, `": "` key separator, `{}`/`[]` for empty containers, and
/// control-character escaping with lowercase hex.
public static class Json
{
    public static string Pretty(object? value)
    {
        var sb = new StringBuilder();
        Write(sb, value, 0, pretty: true);
        return sb.ToString();
    }

    public static string Compact(object? value)
    {
        var sb = new StringBuilder();
        Write(sb, value, 0, pretty: false);
        return sb.ToString();
    }

    private static void Write(StringBuilder sb, object? value, int depth, bool pretty)
    {
        switch (value)
        {
            case null:
                sb.Append("null");
                break;
            case bool b:
                sb.Append(b ? "true" : "false");
                break;
            case string s:
                WriteString(sb, s);
                break;
            case int i:
                sb.Append(i.ToString(CultureInfo.InvariantCulture));
                break;
            case long l:
                sb.Append(l.ToString(CultureInfo.InvariantCulture));
                break;
            case double d:
                sb.Append(d.ToString("G17", CultureInfo.InvariantCulture));
                break;
            case JsonObject obj:
                WriteObject(sb, obj, depth, pretty);
                break;
            case IEnumerable<KeyValuePair<string, object?>> pairs:
                WriteObject(sb, pairs, depth, pretty);
                break;
            case System.Collections.IEnumerable list:
                WriteArray(sb, list.Cast<object?>(), depth, pretty);
                break;
            default:
                throw new ArgumentException($"Unsupported JSON value type: {value.GetType()}");
        }
    }

    private static void WriteObject(StringBuilder sb, IEnumerable<KeyValuePair<string, object?>> obj, int depth, bool pretty)
    {
        var entries = obj.ToList();
        if (entries.Count == 0)
        {
            sb.Append("{}");
            return;
        }
        sb.Append('{');
        for (var i = 0; i < entries.Count; i++)
        {
            if (pretty)
            {
                sb.Append('\n');
                Indent(sb, depth + 1);
            }
            WriteString(sb, entries[i].Key);
            sb.Append(pretty ? ": " : ":");
            Write(sb, entries[i].Value, depth + 1, pretty);
            if (i < entries.Count - 1)
                sb.Append(',');
        }
        if (pretty)
        {
            sb.Append('\n');
            Indent(sb, depth);
        }
        sb.Append('}');
    }

    private static void WriteArray(StringBuilder sb, IEnumerable<object?> items, int depth, bool pretty)
    {
        var list = items.ToList();
        if (list.Count == 0)
        {
            sb.Append("[]");
            return;
        }
        sb.Append('[');
        for (var i = 0; i < list.Count; i++)
        {
            if (pretty)
            {
                sb.Append('\n');
                Indent(sb, depth + 1);
            }
            Write(sb, list[i], depth + 1, pretty);
            if (i < list.Count - 1)
                sb.Append(',');
        }
        if (pretty)
        {
            sb.Append('\n');
            Indent(sb, depth);
        }
        sb.Append(']');
    }

    private static void Indent(StringBuilder sb, int depth)
    {
        for (var i = 0; i < depth; i++)
            sb.Append("  ");
    }

    private static void WriteString(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (var c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < ' ')
                        sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else
                        sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}
