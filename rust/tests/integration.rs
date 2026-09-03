use std::fs;
use tempfile::TempDir;
use envdoctor::commands::{scan, init, generate};
use envdoctor::commands::shared::OutputFormat;
use envdoctor::commands::generate::{GenerateArgs, GenerateCommand};
use envdoctor::commands::scan::ScanArgs;
use envdoctor::commands::shared::OutputArgs;
use camino::Utf8PathBuf;

fn create_test_project(dir: &TempDir) {
    // Create .env file
    fs::write(
        dir.path().join(".env"),
        "DATABASE_URL=postgres://localhost:5432/myapp\nAPI_KEY=secret123\nDEBUG=true\nPORT=3000\n"
    ).unwrap();

    // Create .env.example
    fs::write(
        dir.path().join(".env.example"),
        "DATABASE_URL=\nAPI_KEY=\nDEBUG=false\nPORT=\n"
    ).unwrap();

    // Create a simple JS file using process.env
    fs::write(
        dir.path().join("config.js"),
        "const db = process.env.DATABASE_URL;\nconst port = process.env.PORT;\nconst missing = process.env.MISSING_SECRET;\n"
    ).unwrap();

    // Create a docker-compose file
    fs::write(
        dir.path().join("docker-compose.yml"),
        "version: '3'\nservices:\n  app:\n    environment:\n      - DATABASE_URL\n      - API_KEY\n      - DEBUG\n"
    ).unwrap();
}

#[tokio::test]
async fn test_scan_finds_issues() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let args = ScanArgs {
        output: OutputArgs {
            format: OutputFormat::Human,
            output: None,
            strict: false,
        },
        root: Some(root),
        ..Default::default()
    };

    let exit_code = scan(args).await.unwrap();
    // Should find issues (missing API_KEY in process.env, etc.)
    assert_eq!(exit_code, 1);
}

#[tokio::test]
async fn test_init_creates_config() {
    let temp = TempDir::new().unwrap();
    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    let args = envdoctor::commands::init::InitArgs {
        root: Some(root.clone()),
        force: true,
    };

    let exit_code = init(args).unwrap();
    assert_eq!(exit_code, 0);

    let config_path = root.join("envdoctor.config.toml");
    assert!(config_path.exists());

    let content = fs::read_to_string(&config_path).unwrap();
    assert!(content.contains("ignoreVariables"));
    assert!(content.contains("rules"));
}

#[tokio::test]
async fn test_generate_env_example() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let args = GenerateArgs {
        command: GenerateCommand::EnvExample,
        root: Some(root.clone()),
        output: None,
    };

    let exit_code = generate(args).await.unwrap();
    assert_eq!(exit_code, 0);

    let example_path = root.join(".env.example");
    assert!(example_path.exists());
    let content = fs::read_to_string(&example_path).unwrap();
    assert!(content.contains("DATABASE_URL"));
    assert!(content.contains("API_KEY"));
}

#[tokio::test]
async fn test_generate_env_doc() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let args = GenerateArgs {
        command: GenerateCommand::EnvDoc,
        root: Some(root.clone()),
        output: None,
    };

    let exit_code = generate(args).await.unwrap();
    assert_eq!(exit_code, 0);
}

#[tokio::test]
async fn test_generate_env_types() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let args = GenerateArgs {
        command: GenerateCommand::EnvTypes,
        root: Some(root.clone()),
        output: None,
    };

    let exit_code = generate(args).await.unwrap();
    assert_eq!(exit_code, 0);
}

#[tokio::test]
async fn test_generate_config_schema() {
    let temp = TempDir::new().unwrap();
    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    let args = GenerateArgs {
        command: GenerateCommand::ConfigSchema,
        root: Some(root.clone()),
        output: None,
    };

    let exit_code = generate(args).await.unwrap();
    assert_eq!(exit_code, 0);
}

#[tokio::test]
async fn test_generate_config_template() {
    let temp = TempDir::new().unwrap();
    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    let args = GenerateArgs {
        command: GenerateCommand::ConfigTemplate,
        root: Some(root.clone()),
        output: None,
    };

    let exit_code = generate(args).await.unwrap();
    assert_eq!(exit_code, 0);
}

#[tokio::test]
async fn test_generate_github_actions() {
    let temp = TempDir::new().unwrap();
    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    let args = GenerateArgs {
        command: GenerateCommand::GithubActions,
        root: Some(root.clone()),
        output: None,
    };

    let exit_code = generate(args).await.unwrap();
    assert_eq!(exit_code, 0);
}

#[tokio::test]
async fn test_scan_json_output() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let args = ScanArgs {
        output: OutputArgs {
            format: OutputFormat::Json,
            output: None,
            strict: false,
        },
        root: Some(root),
        ..Default::default()
    };

    let exit_code = scan(args).await.unwrap();
    assert_eq!(exit_code, 1);
}

#[tokio::test]
async fn test_scan_sarif_output() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let args = ScanArgs {
        output: OutputArgs {
            format: OutputFormat::Sarif,
            output: None,
            strict: false,
        },
        root: Some(root),
        ..Default::default()
    };

    let exit_code = scan(args).await.unwrap();
    assert_eq!(exit_code, 1);
}

#[tokio::test]
async fn test_scan_with_config() {
    let temp = TempDir::new().unwrap();
    create_test_project(&temp);

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    // Baseline: the fixture references MISSING_SECRET in source but never
    // defines it, so the undefined-source detector produces an error → exit 1.
    let baseline = scan(ScanArgs {
        output: OutputArgs {
            format: OutputFormat::Human,
            output: None,
            strict: false,
        },
        root: Some(root.clone()),
        ..Default::default()
    })
    .await
    .unwrap();
    assert_eq!(baseline, 1, "unignored fixture should surface an error");

    // Config keys are camelCase (matching the JSON/package.json convention),
    // even in TOML. Ignoring MISSING_SECRET should suppress the only error and
    // drop the exit code back to 0.
    fs::write(
        temp.path().join("envdoctor.config.toml"),
        "ignoreVariables = [\"MISSING_SECRET\"]\n",
    )
    .unwrap();

    let exit_code = scan(ScanArgs {
        output: OutputArgs {
            format: OutputFormat::Human,
            output: None,
            strict: false,
        },
        root: Some(root),
        ..Default::default()
    })
    .await
    .unwrap();
    assert_eq!(exit_code, 0, "ignoreVariables should suppress the error");
}

#[tokio::test]
async fn test_diff_reports_missing_keys() {
    use envdoctor::commands::diff;
    use envdoctor::commands::diff::DiffArgs;

    let temp = TempDir::new().unwrap();
    fs::write(
        temp.path().join(".env"),
        "DATABASE_URL=postgres://localhost/dev\nDEBUG=true\n",
    )
    .unwrap();
    fs::write(
        temp.path().join(".env.production"),
        "DATABASE_URL=postgres://prod/db\n",
    )
    .unwrap();

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    // Human output: DEBUG is missing in production → exit 1.
    let exit_code = diff(DiffArgs {
        root: Some(root.clone()),
        env_a: "development".to_string(),
        env_b: "production".to_string(),
        json: false,
    })
    .await
    .unwrap();
    assert_eq!(exit_code, 1);

    // JSON output path should also return 1 for the same drift.
    let exit_json = diff(DiffArgs {
        root: Some(root),
        env_a: "development".to_string(),
        env_b: "production".to_string(),
        json: true,
    })
    .await
    .unwrap();
    assert_eq!(exit_json, 1);
}

#[tokio::test]
async fn test_sync_dry_run_does_not_modify_target() {
    use envdoctor::commands::sync;
    use envdoctor::commands::sync::SyncArgs;

    let temp = TempDir::new().unwrap();
    fs::write(
        temp.path().join(".env"),
        "DATABASE_URL=postgres://localhost/dev\nDEBUG=true\nEXTRA_KEY=value\n",
    )
    .unwrap();
    let target = temp.path().join(".env.production");
    fs::write(&target, "DATABASE_URL=postgres://prod/db\n").unwrap();
    let before = fs::read_to_string(&target).unwrap();

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();
    let exit_code = sync(SyncArgs {
        root: Some(root),
        from: "development".to_string(),
        to: "production".to_string(),
        dry_run: true,
    })
    .await
    .unwrap();

    assert_eq!(exit_code, 0);
    let after = fs::read_to_string(&target).unwrap();
    assert_eq!(before, after, "dry run must not modify the target file");
}

#[tokio::test]
async fn test_snapshot_diff_identical_and_differing() {
    use envdoctor::commands::snapshot_diff;
    use envdoctor::commands::snapshot_diff::SnapshotDiffArgs;
    use envdoctor::runtime::capture_snapshot;

    let temp = TempDir::new().unwrap();
    let snapshot = capture_snapshot(false);
    let json = serde_json::to_string(&snapshot).unwrap();

    let a_path = temp.path().join("a.json");
    let b_path = temp.path().join("b.json");
    fs::write(&a_path, &json).unwrap();
    fs::write(&b_path, &json).unwrap();

    let root = Utf8PathBuf::try_from(temp.path().to_path_buf()).unwrap();

    // Identical snapshots → equivalent → exit 0.
    let exit_same = snapshot_diff(SnapshotDiffArgs {
        root: Some(root.clone()),
        a: "a.json".to_string(),
        b: "b.json".to_string(),
        json: false,
    })
    .await
    .unwrap();
    assert_eq!(exit_same, 0);

    // Differing snapshot: add a tool → drift → exit 1.
    let mut other = snapshot.clone();
    other.tools.push(envdoctor::models::ToolInfo {
        tool: "zzz-fake-tool".to_string(),
        version: "9.9.9".to_string(),
        resolved_from: "PATH".to_string(),
    });
    fs::write(&b_path, serde_json::to_string(&other).unwrap()).unwrap();

    let exit_diff = snapshot_diff(SnapshotDiffArgs {
        root: Some(root),
        a: "a.json".to_string(),
        b: "b.json".to_string(),
        json: true,
    })
    .await
    .unwrap();
    assert_eq!(exit_diff, 1);
}

#[test]
fn test_glob_matching() {
    use envdoctor::utils::glob::{matches_glob, matches_any_glob};

    assert!(matches_glob("AWS_*", "AWS_SECRET"));
    assert!(!matches_glob("AWS_*", "GCP_SECRET"));
    assert!(matches_glob("FOO*", "FOO"));
    assert!(matches_glob("FOO*", "FOOBAR"));
    assert!(!matches_glob("FOO*", "BAR"));

    assert!(matches_any_glob(&["AWS_*".to_string(), "GCP_*".to_string()], "AWS_KEY"));
    assert!(matches_any_glob(&["AWS_*".to_string(), "GCP_*".to_string()], "GCP_KEY"));
    assert!(!matches_any_glob(&["AWS_*".to_string(), "GCP_*".to_string()], "AZURE_KEY"));
}

#[test]
fn test_variable_type_inference() {
    use envdoctor::utils::type_infer::infer_type;

    assert_eq!(infer_type(Some("42")), envdoctor::models::VariableType::Integer);
    assert_eq!(infer_type(Some("3.14")), envdoctor::models::VariableType::Float);
    assert_eq!(infer_type(Some("true")), envdoctor::models::VariableType::Boolean);
    assert_eq!(infer_type(Some("false")), envdoctor::models::VariableType::Boolean);
    assert_eq!(infer_type(Some("https://example.com")), envdoctor::models::VariableType::Url);
    assert_eq!(infer_type(Some("http://localhost:3000")), envdoctor::models::VariableType::Url);
    assert_eq!(infer_type(Some(r#"{"key": "value"}"#)), envdoctor::models::VariableType::Json);
    assert_eq!(infer_type(Some("hello")), envdoctor::models::VariableType::String);
    assert_eq!(infer_type(None), envdoctor::models::VariableType::Unknown);
}

#[test]
fn test_secret_detection() {
    use envdoctor::models::EnvironmentVariable;

    assert!(EnvironmentVariable::is_secret_name("API_KEY"));
    assert!(EnvironmentVariable::is_secret_name("SECRET"));
    assert!(EnvironmentVariable::is_secret_name("PASSWORD"));
    assert!(EnvironmentVariable::is_secret_name("TOKEN"));
    assert!(EnvironmentVariable::is_secret_name("PRIVATE_KEY"));
    assert!(!EnvironmentVariable::is_secret_name("DEBUG"));
    assert!(!EnvironmentVariable::is_secret_name("PORT"));
    assert!(!EnvironmentVariable::is_secret_name("NODE_ENV"));
}