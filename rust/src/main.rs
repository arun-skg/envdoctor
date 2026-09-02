use clap::{Parser, Subcommand};
use camino::Utf8PathBuf;
use envdoctor::commands::{
    scan::ScanArgs,
    init::InitArgs,
    fix::FixArgs,
    diff::DiffArgs,
    snapshot::SnapshotArgs,
    snapshot_diff::SnapshotDiffArgs,
    sync::SyncArgs,
    generate::GenerateArgs,
};

#[derive(Parser, Debug)]
#[command(name = "envdoctor", version, about = "Local-first consistency checker for environment variables", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Project root (default: current directory)
    #[arg(long, short = 'C', global = true)]
    root: Option<Utf8PathBuf>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Scan for environment variable issues
    Scan(ScanArgs),
    /// Initialize a new envdoctor config
    Init(InitArgs),
    /// Auto-fix certain issues
    Fix(FixArgs),
    /// Show differences between environments
    Diff(DiffArgs),
    /// Capture runtime snapshot
    Snapshot(SnapshotArgs),
    /// Compare two runtime snapshots (tokens or JSON files)
    SnapshotDiff(SnapshotDiffArgs),
    /// Copy missing keys from one environment file to another
    Sync(SyncArgs),
    /// Generate files from model
    Generate(GenerateArgs),
}

fn main() -> Result<(), anyhow::Error> {
    let cli = Cli::parse();

    // Normalize root path
    let root = cli.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let _root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    // Run the appropriate command in tokio runtime
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    let exit_code = rt.block_on(async {
        match cli.command {
            Commands::Scan(args) => envdoctor::commands::scan(args).await,
            Commands::Init(args) => envdoctor::commands::init(args),
            Commands::Fix(args) => envdoctor::commands::fix(args).await,
            Commands::Diff(args) => envdoctor::commands::diff(args).await,
            Commands::Snapshot(args) => envdoctor::commands::snapshot(args).await,
            Commands::SnapshotDiff(args) => envdoctor::commands::snapshot_diff(args).await,
            Commands::Sync(args) => envdoctor::commands::sync(args).await,
            Commands::Generate(args) => envdoctor::commands::generate(args).await,
        }
    });

    let exit_code = exit_code?;
    std::process::exit(exit_code as i32);
}