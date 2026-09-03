use camino::Utf8PathBuf;
use clap::{Args, Subcommand};

#[derive(Args, Debug)]
pub struct GenerateArgs {
    #[command(subcommand)]
    pub command: GenerateCommand,

    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// Output file (default: stdout)
    #[arg(long, short)]
    pub output: Option<Utf8PathBuf>,
}

#[derive(Subcommand, Debug)]
pub enum GenerateCommand {
    /// Generate .env.example
    EnvExample,
    /// Generate ENVIRONMENT.md documentation
    EnvDoc,
    /// Generate TypeScript types (env.d.ts)
    EnvTypes,
    /// Generate JSON schema for configuration
    ConfigSchema,
    /// Generate TOML config template
    ConfigTemplate,
    /// Generate GitHub Actions workflow snippet
    GithubActions,
}

pub async fn generate(args: GenerateArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let root = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let (model, config) = crate::core::pipeline::load_project(&root).await;

    let output = match args.command {
        GenerateCommand::EnvExample => {
            crate::generators::generate_env_example(&model, &config)
        }
        GenerateCommand::EnvDoc => {
            crate::generators::generate_environment_doc(&model, &config)
        }
        GenerateCommand::EnvTypes => {
            crate::generators::generate_env_types(&model, &config)
        }
        GenerateCommand::ConfigSchema => {
            crate::generators::generate_config_schema()
        }
        GenerateCommand::ConfigTemplate => {
            crate::generators::generate_config_template()
        }
        GenerateCommand::GithubActions => {
            crate::generators::generate_github_actions(&model, &config)
        }
    };

    if let Some(path) = &args.output {
        std::fs::write(path, output)?;
        println!("Written to {}", path);
    } else {
        println!("{}", output);
    }

    Ok(0)
}