use camino::Utf8PathBuf;
use clap::Args;

#[derive(Args, Debug)]
pub struct InitArgs {
    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// Force overwrite existing config
    #[arg(long)]
    pub force: bool,
}

pub fn init(args: InitArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    let config_path = root.join("envdoctor.config.toml");

    if config_path.exists() && !args.force {
        eprintln!("Config already exists at {}. Use --force to overwrite.", config_path);
        return Ok(1);
    }

    let template = crate::generators::generate_config_template();
    std::fs::write(&config_path, template)?;

    println!("Created {}", config_path);
    println!("Edit the file to customize your configuration, then run `envdoctor scan`.");

    Ok(0)
}