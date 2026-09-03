use crate::commands::shared::normalize_env_label;
use crate::core::pipeline::load_project;
use crate::models::EnvironmentVariable;
use camino::Utf8PathBuf;
use clap::Args;
use std::collections::BTreeSet;
use std::io::Write;

#[derive(Args, Debug)]
pub struct SyncArgs {
    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// Source environment (e.g. development, production, or dev/prod aliases)
    pub from: String,

    /// Target environment to receive the missing keys
    pub to: String,

    /// Preview the changes without writing
    #[arg(long)]
    pub dry_run: bool,
}

/// `envdoctor sync <from> <to>` — copy missing variable keys from one
/// environment file to another, using placeholder values. Never copies real
/// secret values.
pub async fn sync(args: SyncArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let from_label = normalize_env_label(&args.from);
    let to_label = normalize_env_label(&args.to);

    let (model, config) = load_project(&root).await;

    let from_names = names_for_environment(&model, &from_label);
    let to_names = names_for_environment(&model, &to_label);

    let missing: Vec<String> = from_names
        .iter()
        .filter(|n| !to_names.contains(*n))
        .cloned()
        .collect();

    if missing.is_empty() {
        println!("✓ {from_label} → {to_label}: nothing to sync");
        return Ok(0);
    }

    let target_file = target_env_path(&root, &to_label, &config);
    let target_rel = target_file
        .strip_prefix(&root)
        .map(|p| p.to_string())
        .unwrap_or_else(|_| target_file.to_string());

    let mut lines: Vec<String> = Vec::new();
    lines.push(String::new());
    lines.push(format!("# Synced from {from_label} by envdoctor"));
    for name in &missing {
        let placeholder = if EnvironmentVariable::is_secret_name(name) {
            String::new()
        } else {
            format!("your_{}", name.to_lowercase())
        };
        lines.push(format!("{name}={placeholder}"));
    }
    let append = lines.join("\n") + "\n";

    if args.dry_run {
        println!("envdoctor sync (dry run)\n");
        println!(
            "Would append {} key{} to {}:",
            missing.len(),
            plural(missing.len()),
            target_rel
        );
        for name in &missing {
            println!("  + {name}");
        }
        return Ok(0);
    }

    if let Some(parent) = target_file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&target_file)?;
    file.write_all(append.as_bytes())?;

    println!("envdoctor sync\n");
    println!(
        "  ✓ Appended {} key{} to {}",
        missing.len(),
        plural(missing.len()),
        target_rel
    );
    for name in &missing {
        println!("    + {name}");
    }

    Ok(0)
}

/// Sorted set of variable names defined for an environment label.
fn names_for_environment(model: &crate::models::ProjectModel, label: &str) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    for file in &model.env_files {
        if file.environment.as_deref() == Some(label) {
            for v in &file.variables {
                names.insert(v.name.clone());
            }
        }
    }
    names
}

/// Resolve the file that should receive synced keys for a target label.
fn target_env_path(
    root: &Utf8PathBuf,
    label: &str,
    config: &crate::config::EnvdoctorConfig,
) -> Utf8PathBuf {
    if let Some(environments) = &config.environments {
        if let Some(files) = environments.get(label) {
            if let Some(first) = files.first() {
                return root.join(first);
            }
        }
    }
    if label == "development" {
        root.join(".env")
    } else {
        root.join(format!(".env.{label}"))
    }
}

fn plural(n: usize) -> &'static str {
    if n == 1 {
        ""
    } else {
        "s"
    }
}
