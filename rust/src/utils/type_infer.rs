use crate::models::VariableType;
use std::sync::LazyLock;

static INTEGER_RE: LazyLock<regex::Regex> = LazyLock::new(|| regex::Regex::new(r"^-?\d+$").unwrap());
static FLOAT_RE: LazyLock<regex::Regex> = LazyLock::new(|| regex::Regex::new(r"^-?\d+\.\d+([eE][+-]?\d+)?$").unwrap());
static BOOLEAN_RE: LazyLock<regex::Regex> = LazyLock::new(|| regex::Regex::new(r"^(true|false|TRUE|FALSE)$").unwrap());
static URL_RE: LazyLock<regex::Regex> = LazyLock::new(|| regex::Regex::new(r"^https?://\S+$").unwrap());

/// Infer the basic type of a variable value. Ordering matters: a value like
/// "1" is an integer, "1.5" is a float, "true" is a boolean, and a URL wins
/// over generic string. Anything unparseable or empty is "string" or "unknown".
pub fn infer_type(value: Option<&str>) -> VariableType {
    let Some(value) = value else {
        return VariableType::Unknown;
    };
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return VariableType::Unknown;
    }
    if INTEGER_RE.is_match(trimmed) {
        return VariableType::Integer;
    }
    if FLOAT_RE.is_match(trimmed) {
        return VariableType::Float;
    }
    if BOOLEAN_RE.is_match(trimmed) {
        return VariableType::Boolean;
    }
    if URL_RE.is_match(trimmed) {
        return VariableType::Url;
    }
    if trimmed.starts_with('{') || trimmed.starts_with('[') {
        if serde_json::from_str::<serde_json::Value>(trimmed).is_ok() {
            return VariableType::Json;
        }
    }
    VariableType::String
}