use serde::{Deserialize, Serialize};

/// The basic value types envdoctor can infer from a variable's value.
/// Inference lives in `utils/type_infer.rs`; detectors compare these across
/// environments to surface type mismatches.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VariableType {
    Integer,
    Float,
    Boolean,
    Url,
    Json,
    String,
    Unknown,
}

impl VariableType {
    pub fn as_str(&self) -> &'static str {
        match self {
            VariableType::Integer => "integer",
            VariableType::Float => "float",
            VariableType::Boolean => "boolean",
            VariableType::Url => "url",
            VariableType::Json => "json",
            VariableType::String => "string",
            VariableType::Unknown => "unknown",
        }
    }
}

impl std::fmt::Display for VariableType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}