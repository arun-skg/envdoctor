use crate::core::audit::run_audit;
use crate::core::exit_codes::audit_exit_code;
use crate::core::pipeline::load_project;
use crate::detectors::index::build_index;
use crate::generators::{
    collect_actions_checklist, generate_actions_checklist, generate_env_example,
    generate_env_types, generate_environment_doc, generate_variable_schema_ts,
};
use crate::models::ExitContext;
use camino::Utf8PathBuf;
use clap::Args;

#[derive(Args, Debug)]
pub struct FixArgs {
    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// Preview changes without writing any files
    #[arg(long)]
    pub dry_run: bool,

    /// Overwrite files that already exist (default: skip them)
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Action {
    Create,
    Update,
    Skip,
}

struct PlannedFile {
    rel_path: String,
    action: Action,
    content: String,
}

/// `envdoctor fix` — run the audit, then regenerate the safe, generated
/// artifacts: `.env.example`, `ENVIRONMENT.md`, `env.d.ts`,
/// `envdoctor.schema.ts`, and (when the project uses GitHub Actions
/// secrets/vars) `.github/ENVIRONMENT.md`. Never touches real `.env` files and
/// never writes secret values. `--dry-run` previews changes.
pub async fn fix(args: FixArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.clone().unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let (model, config) = load_project(&root).await;
    let index = build_index(&model);
    let findings = run_audit(&model, &config, &index);
    let exit_code = audit_exit_code(&ExitContext {
        findings: findings.clone(),
        strict: false,
    });

    let checklist = collect_actions_checklist(&model);
    let has_actions_refs = !checklist.secrets.is_empty() || !checklist.vars.is_empty();

    let mut plans = vec![
        plan(&root, ".env.example", generate_env_example(&model, &config), &args),
        plan(&root, "ENVIRONMENT.md", generate_environment_doc(&model, &config), &args),
        plan(&root, "env.d.ts", generate_env_types(&model, &config), &args),
        plan(&root, "envdoctor.schema.ts", generate_variable_schema_ts(&model), &args),
    ];
    if has_actions_refs {
        plans.push(plan(
            &root,
            ".github/ENVIRONMENT.md",
            generate_actions_checklist(&model),
            &args,
        ));
    }

    if args.dry_run {
        println!("envdoctor fix (dry run)\n");
        for p in &plans {
            let marker = match p.action {
                Action::Create => "+",
                Action::Update => "~",
                Action::Skip => "·",
            };
            println!("  {} {}  {}", marker, p.rel_path, action_label(p.action));
        }
        let pending = plans.iter().filter(|p| p.action != Action::Skip).count();
        println!("\n  {} change{} planned", pending, plural(pending));
        return Ok(exit_code);
    }

    let mut created = 0usize;
    let mut updated = 0usize;
    for p in &plans {
        if p.action == Action::Skip {
            continue;
        }
        let full = root.join(&p.rel_path);
        if let Some(parent) = full.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&full, &p.content)?;
        match p.action {
            Action::Create => created += 1,
            Action::Update => updated += 1,
            Action::Skip => {}
        }
    }

    println!("envdoctor fix\n");
    for p in &plans {
        match p.action {
            Action::Skip => println!(
                "  · skipped {} (exists; use --force to overwrite)",
                p.rel_path
            ),
            Action::Create => println!("  ✓ created {}", p.rel_path),
            Action::Update => println!("  ✓ updated {}", p.rel_path),
        }
    }
    let errors = findings
        .iter()
        .filter(|f| f.severity == crate::models::Severity::Error)
        .count();
    println!(
        "\n  {} created, {} updated · {} error{} still present",
        created,
        updated,
        errors,
        plural(errors)
    );

    Ok(exit_code)
}

fn plan(root: &Utf8PathBuf, rel_path: &str, content: String, args: &FixArgs) -> PlannedFile {
    let exists = root.join(rel_path).exists();
    let action = if !exists {
        Action::Create
    } else if args.force {
        Action::Update
    } else {
        Action::Skip
    };
    PlannedFile {
        rel_path: rel_path.to_string(),
        action,
        content,
    }
}

fn action_label(action: Action) -> &'static str {
    match action {
        Action::Create => "will create",
        Action::Update => "will update",
        Action::Skip => "exists",
    }
}

fn plural(n: usize) -> &'static str {
    if n == 1 {
        ""
    } else {
        "s"
    }
}
