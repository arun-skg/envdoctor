use serde::{Deserialize, Serialize};

/// Schema version for the runtime snapshot format.
pub const SNAPSHOT_SCHEMA: &str = "envdoctor.runtime-snapshot.v1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSnapshot {
    pub schema: String,
    pub captured_at: String,
    pub os: OsInfo,
    pub tools: Vec<ToolInfo>,
    pub path: Vec<String>,
    pub globals: std::collections::HashMap<String, Vec<GlobalPackage>>,
    pub env_flag_names: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OsInfo {
    pub platform: String,
    pub arch: String,
    pub release: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolInfo {
    pub tool: String,
    pub version: String,
    pub resolved_from: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GlobalPackage {
    pub name: String,
    pub version: String,
}