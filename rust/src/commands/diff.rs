use crate::commands::shared::{normalize_env_label, report_parse_errors};
use crate::core::pipeline::load_project;
use crate::detectors::environment_diff::compare_environments;
use camino::Utf8PathBuf;
use clap::Args;
use std::collections::BTreeSet;

#[derive(Args, Debug)]
pub struct DiffArgs {
    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// First environment (e.g. development, production, or dev/prod aliases)
    pub env_a: String,

    /// Second environment
    pub env_b: String,

    /// Print the diff as JSON
    #[arg(long)]
    pub json: bool,
}

/// `envdoctor diff <env1> <env2>` — compare variable sets across environments.
pub async fn diff(args: DiffArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let (model, _config) = load_project(&root).await;
    let label_a = normalize_env_label(&args.env_a);
    let label_b = normalize_env_label(&args.env_b);

    let available: BTreeSet<String> = model
        .env_files
        .iter()
        .filter_map(|f| f.environment.clone())
        .filter(|e| e != "example")
        .collect();

    report_parse_errors(&model, &root);

    if !available.contains(&label_a) || !available.contains(&label_b) {
        if !available.contains(&label_a) {
            eprintln!("error Environment \"{label_a}\" has no files in this project.");
        }
        if !available.contains(&label_b) {
            eprintln!("error Environment \"{label_b}\" has no files in this project.");
        }
        let list: Vec<&String> = available.iter().collect();
        let joined = if list.is_empty() {
            "none".to_string()
        } else {
            list.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", ")
        };
        eprintln!("  Available: {joined}");
        return Ok(2);
    }

    let entries = compare_environments(&model, &label_a, &label_b);
    let missing_count = entries.iter().filter(|e| !e.present_in_both).count();

    if args.json {
        let variables: Vec<serde_json::Value> = entries
            .iter()
            .map(|e| {
                let missing_in = if e.present_in_both {
                    serde_json::Value::Null
                } else if e.present_in_a {
                    serde_json::json!(label_b)
                } else {
                    serde_json::json!(label_a)
                };
                serde_json::json!({
                    "name": e.name,
                    "status": if e.present_in_both { "same" } else { "missing" },
                    "missingIn": missing_in,
                })
            })
            .collect();
        let out = serde_json::json!({
            "environments": [label_a, label_b],
            "exitCode": if missing_count > 0 { 1 } else { 0 },
            "total": entries.len(),
            "missing": missing_count,
            "variables": variables,
        });
        println!("{}", serde_json::to_string_pretty(&out)?);
        return Ok(if missing_count > 0 { 1 } else { 0 });
    }

    println!("ENVIRONMENT DIFF");
    println!("{}\n", "=".repeat("ENVIRONMENT DIFF".len() * 2));
    println!("  {label_a} → {label_b}\n");

    for entry in &entries {
        if entry.present_in_both {
            println!("  = {}  present in both", entry.name);
        } else if entry.present_in_a {
            println!("  ✗ {}  missing in {}", entry.name, label_b);
        } else {
            println!("  ✗ {}  missing in {}", entry.name, label_a);
        }
    }
    println!(
        "\n  Summary: {} variables · {} missing · {} present in both",
        entries.len(),
        missing_count,
        entries.len() - missing_count
    );

    Ok(if missing_count > 0 { 1 } else { 0 })
}
