use crate::core::exit_codes::{EXIT_ISSUES, EXIT_OK, EXIT_USAGE};
use crate::models::RuntimeSnapshot;
use crate::runtime::compare::RuntimeStatus;
use crate::runtime::{compare_snapshots, decode_token, parse_snapshot_json, RuntimeDiff};
use camino::Utf8PathBuf;
use clap::Args;

#[derive(Args, Debug)]
pub struct SnapshotDiffArgs {
    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// First snapshot — a token (`envd1:…`) or a path to a snapshot JSON file
    pub a: String,

    /// Second snapshot — a token (`envd1:…`) or a path to a snapshot JSON file
    pub b: String,

    /// Print the diff as JSON
    #[arg(long)]
    pub json: bool,
}

/// Resolve a positional arg that may be a token string or a file path.
fn load_snapshot(root: &Utf8PathBuf, arg: &str) -> anyhow::Result<RuntimeSnapshot> {
    if arg.trim().starts_with("envd1:") {
        return decode_token(arg);
    }
    let file = root.join(arg);
    if !file.exists() {
        anyhow::bail!("Not a snapshot token, and file not found: {arg}");
    }
    parse_snapshot_json(&std::fs::read_to_string(&file)?)
}

/// `envdoctor snapshot-diff <a> <b>` — compare two runtime snapshots.
pub async fn snapshot_diff(args: SnapshotDiffArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let a = match load_snapshot(&root, &args.a) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error {e}");
            return Ok(EXIT_USAGE);
        }
    };
    let b = match load_snapshot(&root, &args.b) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error {e}");
            return Ok(EXIT_USAGE);
        }
    };

    let diff = compare_snapshots(&a, &b);

    if args.json {
        let mut value = serde_json::to_value(&diff)?;
        if let Some(obj) = value.as_object_mut() {
            obj.insert(
                "exitCode".to_string(),
                serde_json::json!(if diff.equivalent { 0 } else { 1 }),
            );
        }
        println!("{}", serde_json::to_string_pretty(&value)?);
        return Ok(if diff.equivalent { EXIT_OK } else { EXIT_ISSUES });
    }

    render_human(&diff);
    Ok(if diff.equivalent { EXIT_OK } else { EXIT_ISSUES })
}

fn render_human(diff: &RuntimeDiff) {
    println!("RUNTIME DIFF");
    println!("{}\n", "=".repeat("RUNTIME DIFF".len() * 2));
    println!("  A → B\n");

    match diff.os.status {
        RuntimeStatus::Same => println!("  = OS  {}\n", diff.os.a),
        _ => println!("  ≠ OS  {} → {}\n", diff.os.a, diff.os.b),
    }

    println!("  Tools");
    for t in &diff.tools {
        let a = t.a.clone().unwrap_or_default();
        let b = t.b.clone().unwrap_or_default();
        match t.status {
            RuntimeStatus::Same => println!("  = {:<8} {}", t.name, a),
            RuntimeStatus::Different => println!("  ≠ {:<8} {} → {}", t.name, a, b),
            RuntimeStatus::OnlyA => println!("  ✗ {:<8} missing in B (A: {})", t.name, a),
            RuntimeStatus::OnlyB => println!("  ✗ {:<8} missing in A (B: {})", t.name, b),
        }
    }

    if diff.path_reordered || !diff.path_only_a.is_empty() || !diff.path_only_b.is_empty() {
        println!("\n  PATH");
        if diff.path_reordered {
            println!("  ≠ same entries, different order");
        }
        for p in &diff.path_only_a {
            println!("  ✗ only in A: {p}");
        }
        for p in &diff.path_only_b {
            println!("  ✗ only in B: {p}");
        }
    }

    if !diff.globals.is_empty() {
        println!("\n  Globals");
        for g in &diff.globals {
            let label = format!("{}:{}", g.ecosystem, g.name);
            match g.status {
                RuntimeStatus::Different => println!(
                    "  ≠ {}  {} → {}",
                    label,
                    g.a.clone().unwrap_or_default(),
                    g.b.clone().unwrap_or_default()
                ),
                RuntimeStatus::OnlyA => println!("  ✗ {label}  missing in B"),
                RuntimeStatus::OnlyB => println!("  ✗ {label}  missing in A"),
                RuntimeStatus::Same => {}
            }
        }
    }

    if diff.equivalent {
        println!("\n  ✓ runtimes are equivalent");
    } else {
        println!("\n  ✗ runtime drift detected");
    }
}
