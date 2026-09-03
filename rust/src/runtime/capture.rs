//! Live-machine runtime snapshot capture — the Rust counterpart of the
//! TypeScript `runtime/collectors.ts` + `runtime/snapshot.ts`.
//!
//! Captures the current machine's OS, installed tool versions, `$PATH`, opt-in
//! global package inventory, and the *names* of non-secret environment
//! variables. Secret-looking names are dropped, never masked, and values are
//! never captured.

use crate::models::runtime_snapshot::{GlobalPackage, OsInfo, ToolInfo};
use crate::models::runtime_snapshot::SNAPSHOT_SCHEMA;
use crate::models::{EnvironmentVariable, RuntimeSnapshot};
use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};

/// Tools probed by default. Order here is the display order before sorting.
const TOOL_PROBES: &[(&str, &[&str])] = &[
    ("node", &["-v"]),
    ("python3", &["--version"]),
    ("python", &["--version"]),
    ("go", &["version"]),
    ("rustc", &["-V"]),
    ("java", &["-version"]),
    ("ruby", &["-v"]),
    ("php", &["-v"]),
    ("perl", &["-v"]),
    ("cc", &["--version"]),
    ("git", &["--version"]),
];

/// Collapse a leading `$HOME` to `~` so snapshots don't leak usernames and stay
/// comparable across machines.
fn collapse_home(p: &str) -> String {
    if let Some(home) = std::env::var_os("HOME").map(|h| h.to_string_lossy().into_owned()) {
        if !home.is_empty() && (p == home || p.starts_with(&format!("{home}/"))) {
            return format!("~{}", &p[home.len()..]);
        }
    }
    p.to_string()
}

/// Ordered, de-duplicated `$PATH` entries with `$HOME` collapsed. Order matters.
fn collect_path() -> Vec<String> {
    let raw = std::env::var("PATH").unwrap_or_default();
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for part in raw.split(':') {
        if part.is_empty() {
            continue;
        }
        let entry = collapse_home(part);
        if seen.insert(entry.clone()) {
            out.push(entry);
        }
    }
    out
}

/// Non-secret env var NAMES only, sorted. Secret-looking names are dropped.
fn collect_env_flag_names() -> Vec<String> {
    let mut names: Vec<String> = std::env::vars()
        .map(|(k, _)| k)
        .filter(|name| !EnvironmentVariable::is_secret_name(name))
        .collect();
    names.sort();
    names
}

/// First dotted version-looking token in a tool's output (e.g. `1.2.3`).
fn extract_version(text: &str) -> Option<String> {
    let re = regex::Regex::new(r"(\d+\.\d+(?:\.\d+)?)").unwrap();
    re.captures(text)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_string())
}

/// Probe one CLI's version; returns `None` when the tool isn't installed.
fn probe_version(tool: &str, args: &[&str]) -> Option<String> {
    let output = std::process::Command::new(tool).args(args).output().ok()?;
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    extract_version(&combined)
}

/// Locate which PATH directory a command resolves from, `$HOME` collapsed.
fn resolve_from(tool: &str) -> String {
    let output = std::process::Command::new("which").arg(tool).output();
    if let Ok(out) = output {
        if out.status.success() {
            let stdout = String::from_utf8_lossy(&out.stdout);
            if let Some(first) = stdout.lines().find(|l| !l.trim().is_empty()) {
                let dir = std::path::Path::new(first.trim())
                    .parent()
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_default();
                return collapse_home(&dir);
            }
        }
    }
    String::new()
}

/// Probe every known tool; only installed ones appear, sorted by name.
fn collect_tools() -> Vec<ToolInfo> {
    let mut tools: Vec<ToolInfo> = TOOL_PROBES
        .iter()
        .filter_map(|(tool, args)| {
            let version = probe_version(tool, args)?;
            Some(ToolInfo {
                tool: tool.to_string(),
                version,
                resolved_from: resolve_from(tool),
            })
        })
        .collect();
    tools.sort_by(|a, b| a.tool.cmp(&b.tool));
    tools
}

/// Global package inventory, opt-in because it is slow. Best-effort per
/// ecosystem (currently npm).
fn collect_globals() -> std::collections::HashMap<String, Vec<GlobalPackage>> {
    let mut globals = std::collections::HashMap::new();
    if let Ok(out) = std::process::Command::new("npm")
        .args(["ls", "-g", "--depth=0", "--json"])
        .output()
    {
        let stdout = String::from_utf8_lossy(&out.stdout);
        let pkgs = parse_npm_globals(&stdout);
        if !pkgs.is_empty() {
            globals.insert("npm".to_string(), pkgs);
        }
    }
    globals
}

/// Parse `npm ls -g --json` into a name/version list; tolerant of partial JSON.
fn parse_npm_globals(stdout: &str) -> Vec<GlobalPackage> {
    let parsed: serde_json::Value = match serde_json::from_str(stdout) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };
    let deps = match parsed.get("dependencies").and_then(|d| d.as_object()) {
        Some(d) => d,
        None => return Vec::new(),
    };
    let mut pkgs: Vec<GlobalPackage> = deps
        .iter()
        .map(|(name, meta)| GlobalPackage {
            name: name.clone(),
            version: meta
                .get("version")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        })
        .collect();
    pkgs.sort_by(|a, b| a.name.cmp(&b.name));
    pkgs
}

/// OS release string (`uname -r` on unix), best-effort.
fn os_release() -> String {
    std::process::Command::new("uname")
        .arg("-r")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

/// Capture this machine's live runtime. `globals` opts into the slow package
/// inventory.
pub fn capture_snapshot(globals: bool) -> RuntimeSnapshot {
    let captured_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_default();

    RuntimeSnapshot {
        schema: SNAPSHOT_SCHEMA.to_string(),
        captured_at,
        os: OsInfo {
            platform: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
            release: os_release(),
        },
        tools: collect_tools(),
        path: collect_path(),
        globals: if globals {
            collect_globals()
        } else {
            std::collections::HashMap::new()
        },
        env_flag_names: collect_env_flag_names(),
    }
}
