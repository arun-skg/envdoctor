pub mod audit;
pub mod discover;
pub mod model;
pub mod pipeline;
pub mod exit_codes;

pub use audit::run_audit;
pub use discover::{discover_files, discover_source_files, GitFilter, ALWAYS_IGNORED};
pub use model::assemble_model;
pub use pipeline::load_project;
pub use exit_codes::{audit_exit_code, EXIT_OK, EXIT_ISSUES, EXIT_USAGE};
