namespace Envdoctor.Models;

/// The basic value types envdoctor can infer from a variable's value.
public enum VariableType
{
    Integer,
    Float,
    Boolean,
    Url,
    Json,
    String,
    Unknown,
}

public static class VariableTypeExtensions
{
    public static string AsStr(this VariableType t) => t switch
    {
        VariableType.Integer => "integer",
        VariableType.Float => "float",
        VariableType.Boolean => "boolean",
        VariableType.Url => "url",
        VariableType.Json => "json",
        VariableType.String => "string",
        VariableType.Unknown => "unknown",
        _ => "unknown",
    };
}
