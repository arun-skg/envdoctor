use crate::core::exit_codes::EXIT_OK;
use crate::runtime::{capture_snapshot, encode_token};
use camino::Utf8PathBuf;
use clap::Args;

#[derive(Args, Debug)]
pub struct SnapshotArgs {
    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// Write the snapshot JSON to a file
    #[arg(long, short)]
    pub output: Option<Utf8PathBuf>,

    /// Print a compact, paste-safe token instead of a human summary
    #[arg(long)]
    pub token: bool,

    /// Print the raw snapshot JSON
    #[arg(long)]
    pub json: bool,

    /// Include the (slow) global package inventory
    #[arg(long)]
    pub globals: bool,
}

/// `envdoctor snapshot` — capture this machine's live runtime.
pub async fn snapshot(args: SnapshotArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let snapshot = capture_snapshot(args.globals);

    if let Some(output) = &args.output {
        let dest = root.join(output);
        std::fs::write(&dest, serde_json::to_string_pretty(&snapshot)? + "\n")?;
        eprintln!("✓ Snapshot written to {}", output);
    }

    if args.json {
        println!("{}", serde_json::to_string_pretty(&snapshot)?);
        return Ok(EXIT_OK);
    }

    if args.token {
        println!("{}", encode_token(&snapshot)?);
        return Ok(EXIT_OK);
    }

    // Human summary.
    println!("RUNTIME SNAPSHOT");
    println!("{}\n", "=".repeat("RUNTIME SNAPSHOT".len() * 2));
    println!(
        "  OS  {}/{} {}\n",
        snapshot.os.platform, snapshot.os.arch, snapshot.os.release
    );

    println!("  Tools");
    if snapshot.tools.is_empty() {
        println!("  none detected");
    } else {
        for t in &snapshot.tools {
            println!("  = {:<8} {}  {}", t.tool, t.version, t.resolved_from);
        }
    }

    println!("\n  PATH ({} entries)", snapshot.path.len());
    for (i, p) in snapshot.path.iter().take(12).enumerate() {
        println!("  {:>2}  {}", i + 1, p);
    }
    if snapshot.path.len() > 12 {
        println!("  … {} more", snapshot.path.len() - 12);
    }

    let ecosystems: Vec<&String> = snapshot.globals.keys().collect();
    if !ecosystems.is_empty() {
        println!("\n  Globals");
        for eco in ecosystems {
            println!(
                "  {}: {} packages",
                eco,
                snapshot.globals.get(eco).map(|v| v.len()).unwrap_or(0)
            );
        }
    } else if !args.globals {
        println!("\n  Globals omitted — pass --globals to include the package inventory.");
    }

    println!(
        "\n  Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>"
    );

    Ok(EXIT_OK)
}
