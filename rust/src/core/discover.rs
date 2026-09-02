use crate::config::EnvdoctorConfig;
use camino::Utf8PathBuf;
use crate::utils::glob::matches_glob;
use glob::glob;
use std::collections::HashSet;
use walkdir::WalkDir;

/// Always-ignored directories and files during discovery.
pub const ALWAYS_IGNORED: &[&str] = &[
    "node_modules",
    ".git",
    "dist",
    "build",
    ".next",
    ".turbo",
    ".vercel",
    ".netlify",
    "coverage",
    ".nyc_output",
    "target",
    ".cargo",
    "vendor",
    "Pods",
    ".idea",
    ".vscode",
    "*.log",
    "*.tmp",
    "*.swp",
    "*.swo",
    "~*",
    "*.DS_Store",
];

/// Git-aware file filter: tracks whether we're in a repo and can run `git
/// check-ignore` / `git diff` / `git ls-files`.
#[derive(Debug, Clone)]
pub struct GitFilter {
    pub root: Utf8PathBuf,
    pub is_repo: bool,
    pub tracked_files: HashSet<String>,
}

impl GitFilter {
    /// Create a new filter for the given root. Runs `git status` to check if
    /// it's a repo.
    pub fn new(root: &Utf8PathBuf) -> Self {
        let is_repo = Self::check_repo(root);
        let tracked_files = if is_repo {
            Self::list_tracked_files(root)
        } else {
            HashSet::new()
        };
        Self {
            root: root.clone(),
            is_repo,
            tracked_files,
        }
    }

    fn check_repo(root: &Utf8PathBuf) -> bool {
        std::process::Command::new("git")
            .args(["rev-parse", "--is-inside-work-tree"])
            .current_dir(root)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    fn list_tracked_files(root: &Utf8PathBuf) -> HashSet<String> {
        let output = std::process::Command::new("git")
            .args(["ls-files", "-z"])
            .current_dir(root)
            .output();
        match output {
            Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout)
                .split('\0')
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string())
                .collect(),
            _ => HashSet::new(),
        }
    }

    /// Should this file be skipped? Returns true to skip.
    pub fn should_skip(&self, path: &Utf8PathBuf) -> bool {
        // Check always-ignored patterns first (fast path)
        let file_name = path.file_name().unwrap_or("");
        for pattern in ALWAYS_IGNORED {
            if matches_glob(pattern, file_name) {
                return true;
            }
        }

        // If not a git repo, rely on patterns only
        if !self.is_repo {
            return false;
        }

        // Get relative path
        let rel = path.strip_prefix(&self.root).ok().and_then(|p| Some(p.as_str()));
        let Some(rel) = rel else { return false };

        // Skip if git ignores it (via .gitignore)
        let ignored = std::process::Command::new("git")
            .args(["check-ignore", "-q", rel])
            .current_dir(&self.root)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        ignored
    }
}

/// Discover all files matching the configured glob patterns.
pub fn discover_files(root: &Utf8PathBuf, config: &EnvdoctorConfig) -> Vec<Utf8PathBuf> {
    let mut results = Vec::new();
    let patterns = [
        &config.env_file_patterns,
        &config.compose_file_patterns,
        &config.actions_file_patterns,
        &config.k8s_file_patterns,
    ];

    let git_filter = GitFilter::new(root);

    for pattern_group in &patterns {
        for pattern in *pattern_group {
            let full_pattern = root.join(pattern);
            if let Ok(paths) = glob(full_pattern.as_str()) {
                for entry in paths.flatten() {
                    let path = Utf8PathBuf::from_path_buf(entry).ok();
                    if let Some(p) = path {
                        if !git_filter.should_skip(&p) {
                            results.push(p);
                        }
                    }
                }
            }
        }
    }

    // Deduplicate and sort
    results.sort();
    results.dedup();
    results
}

/// Discover source files for usage scanning.
pub fn discover_source_files(root: &Utf8PathBuf, config: &EnvdoctorConfig) -> Vec<Utf8PathBuf> {
    let mut results = Vec::new();
    let git_filter = GitFilter::new(root);

    // Walk directory and match extensions
    for entry in WalkDir::new(root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        let path = Utf8PathBuf::from_path_buf(entry.path().to_path_buf()).ok();
        let Some(p) = path else { continue };

        if git_filter.should_skip(&p) {
            continue;
        }

        // Check extension
        let ext = p.extension().unwrap_or("");
        if config.source_extensions.iter().any(|e| e == ext) {
            results.push(p);
        }
    }

    results.sort();
    results.dedup();
    results
}

/// Get files changed since a commit/branch (for `diff` command).
#[allow(dead_code)]
pub fn changed_files_since(root: &Utf8PathBuf, since: &str) -> Vec<Utf8PathBuf> {
    let output = std::process::Command::new("git")
        .args(["diff", "--name-only", since])
        .current_dir(root)
        .output();
    match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter_map(|l| Some(root.join(l)))
            .collect(),
        _ => Vec::new(),
    }
}

/// Get currently staged files.
#[allow(dead_code)]
pub fn staged_files(root: &Utf8PathBuf) -> Vec<Utf8PathBuf> {
    let output = std::process::Command::new("git")
        .args(["diff", "--name-only", "--cached"])
        .current_dir(root)
        .output();
    match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter_map(|l| Some(root.join(l)))
            .collect(),
        _ => Vec::new(),
    }
}