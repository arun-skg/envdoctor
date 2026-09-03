//! Pure comparison of two runtime snapshots. Mirrors the TypeScript
//! `runtime/compare.ts`. `captured_at` is ignored.

use crate::models::runtime_snapshot::GlobalPackage;
use crate::models::RuntimeSnapshot;
use serde::Serialize;
use std::collections::{BTreeSet, HashMap};

/// How an item relates across two snapshots.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum RuntimeStatus {
    Same,
    Different,
    OnlyA,
    OnlyB,
}

#[derive(Debug, Clone, Serialize)]
pub struct OsDiff {
    pub status: RuntimeStatus,
    pub a: String,
    pub b: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ToolDiff {
    pub name: String,
    pub status: RuntimeStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct GlobalDiff {
    pub ecosystem: String,
    pub name: String,
    pub status: RuntimeStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeDiff {
    pub os: OsDiff,
    pub tools: Vec<ToolDiff>,
    /// True when both share the same PATH entries but in a different order.
    pub path_reordered: bool,
    pub path_only_a: Vec<String>,
    pub path_only_b: Vec<String>,
    pub globals: Vec<GlobalDiff>,
    pub env_flag_only_a: Vec<String>,
    pub env_flag_only_b: Vec<String>,
    /// True when nothing meaningful differs (drift-free).
    pub equivalent: bool,
}

fn status_for(a: Option<&String>, b: Option<&String>) -> RuntimeStatus {
    match (a, b) {
        (Some(x), Some(y)) => {
            if x == y {
                RuntimeStatus::Same
            } else {
                RuntimeStatus::Different
            }
        }
        (Some(_), None) => RuntimeStatus::OnlyA,
        (None, _) => RuntimeStatus::OnlyB,
    }
}

fn diff_tools(a: &RuntimeSnapshot, b: &RuntimeSnapshot) -> Vec<ToolDiff> {
    let av: HashMap<&str, &String> = a.tools.iter().map(|t| (t.tool.as_str(), &t.version)).collect();
    let bv: HashMap<&str, &String> = b.tools.iter().map(|t| (t.tool.as_str(), &t.version)).collect();
    let names: BTreeSet<&str> = av.keys().chain(bv.keys()).copied().collect();
    names
        .into_iter()
        .map(|name| ToolDiff {
            name: name.to_string(),
            status: status_for(av.get(name).copied(), bv.get(name).copied()),
            a: av.get(name).map(|s| s.to_string()),
            b: bv.get(name).map(|s| s.to_string()),
        })
        .collect()
}

fn diff_globals(a: &RuntimeSnapshot, b: &RuntimeSnapshot) -> Vec<GlobalDiff> {
    let index = |list: Option<&Vec<GlobalPackage>>| -> HashMap<String, String> {
        list.map(|l| l.iter().map(|p| (p.name.clone(), p.version.clone())).collect())
            .unwrap_or_default()
    };
    let ecosystems: BTreeSet<&String> = a.globals.keys().chain(b.globals.keys()).collect();
    let mut out = Vec::new();
    for eco in ecosystems {
        let av = index(a.globals.get(eco));
        let bv = index(b.globals.get(eco));
        let names: BTreeSet<&String> = av.keys().chain(bv.keys()).collect();
        for name in names {
            let status = status_for(av.get(name), bv.get(name));
            if status == RuntimeStatus::Same {
                continue;
            }
            out.push(GlobalDiff {
                ecosystem: eco.clone(),
                name: name.clone(),
                status,
                a: av.get(name).cloned(),
                b: bv.get(name).cloned(),
            });
        }
    }
    out.sort_by(|x, y| x.name.cmp(&y.name));
    out
}

/// Set difference preserving A's order.
fn only_in(a: &[String], b: &[String]) -> Vec<String> {
    let set: std::collections::HashSet<&String> = b.iter().collect();
    a.iter().filter(|x| !set.contains(x)).cloned().collect()
}

/// Pure comparison of two runtime snapshots.
pub fn compare_snapshots(a: &RuntimeSnapshot, b: &RuntimeSnapshot) -> RuntimeDiff {
    let tools = diff_tools(a, b);
    let path_only_a = only_in(&a.path, &b.path);
    let path_only_b = only_in(&b.path, &a.path);
    let path_reordered =
        path_only_a.is_empty() && path_only_b.is_empty() && a.path.join("\0") != b.path.join("\0");
    let globals = diff_globals(a, b);
    let env_flag_only_a = only_in(&a.env_flag_names, &b.env_flag_names);
    let env_flag_only_b = only_in(&b.env_flag_names, &a.env_flag_names);

    let os_same = a.os.platform == b.os.platform
        && a.os.arch == b.os.arch
        && a.os.release == b.os.release;
    let fmt_os = |s: &RuntimeSnapshot| format!("{}/{} {}", s.os.platform, s.os.arch, s.os.release);

    let equivalent = tools.iter().all(|t| t.status == RuntimeStatus::Same)
        && !path_reordered
        && path_only_a.is_empty()
        && path_only_b.is_empty()
        && globals.is_empty();

    RuntimeDiff {
        os: OsDiff {
            status: if os_same {
                RuntimeStatus::Same
            } else {
                RuntimeStatus::Different
            },
            a: fmt_os(a),
            b: fmt_os(b),
        },
        tools,
        path_reordered,
        path_only_a,
        path_only_b,
        globals,
        env_flag_only_a,
        env_flag_only_b,
        equivalent,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::runtime_snapshot::{OsInfo, ToolInfo, SNAPSHOT_SCHEMA};
    use std::collections::HashMap;

    fn snapshot(tools: Vec<(&str, &str)>, path: Vec<&str>) -> RuntimeSnapshot {
        RuntimeSnapshot {
            schema: SNAPSHOT_SCHEMA.to_string(),
            captured_at: "2026-01-01T00:00:00Z".to_string(),
            os: OsInfo {
                platform: "linux".to_string(),
                arch: "x64".to_string(),
                release: "6.1.0".to_string(),
            },
            tools: tools
                .into_iter()
                .map(|(t, v)| ToolInfo {
                    tool: t.to_string(),
                    version: v.to_string(),
                    resolved_from: "PATH".to_string(),
                })
                .collect(),
            path: path.into_iter().map(|s| s.to_string()).collect(),
            globals: HashMap::new(),
            env_flag_names: Vec::new(),
        }
    }

    #[test]
    fn identical_snapshots_are_equivalent() {
        let a = snapshot(vec![("node", "20.0.0")], vec!["/usr/bin", "/bin"]);
        let b = a.clone();
        let diff = compare_snapshots(&a, &b);
        assert!(diff.equivalent);
        assert!(!diff.path_reordered);
        assert!(diff.path_only_a.is_empty());
        assert!(diff.path_only_b.is_empty());
    }

    #[test]
    fn added_tool_yields_only_b_and_not_equivalent() {
        let a = snapshot(vec![("node", "20.0.0")], vec!["/usr/bin"]);
        let b = snapshot(
            vec![("node", "20.0.0"), ("python", "3.12.0")],
            vec!["/usr/bin"],
        );
        let diff = compare_snapshots(&a, &b);
        assert!(!diff.equivalent);
        let python = diff.tools.iter().find(|t| t.name == "python").unwrap();
        assert_eq!(python.status, RuntimeStatus::OnlyB);

        // Reverse direction: the tool is now only in A.
        let diff_rev = compare_snapshots(&b, &a);
        let python_rev = diff_rev.tools.iter().find(|t| t.name == "python").unwrap();
        assert_eq!(python_rev.status, RuntimeStatus::OnlyA);
    }

    #[test]
    fn differing_path_entry_populates_only_lists() {
        let a = snapshot(vec![("node", "20.0.0")], vec!["/usr/bin", "/opt/a/bin"]);
        let b = snapshot(vec![("node", "20.0.0")], vec!["/usr/bin", "/opt/b/bin"]);
        let diff = compare_snapshots(&a, &b);
        assert_eq!(diff.path_only_a, vec!["/opt/a/bin".to_string()]);
        assert_eq!(diff.path_only_b, vec!["/opt/b/bin".to_string()]);
        assert!(!diff.equivalent);
    }

    #[test]
    fn reordered_but_same_path_sets_reordered_flag() {
        let a = snapshot(vec![("node", "20.0.0")], vec!["/usr/bin", "/bin"]);
        let b = snapshot(vec![("node", "20.0.0")], vec!["/bin", "/usr/bin"]);
        let diff = compare_snapshots(&a, &b);
        assert!(diff.path_reordered);
        assert!(diff.path_only_a.is_empty());
        assert!(diff.path_only_b.is_empty());
        assert!(!diff.equivalent);
    }
}
