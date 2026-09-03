//! envdoctor - Local-first consistency checker for environment variables
//!
//! This is the native Rust port of the TypeScript envdoctor tool.

pub mod commands;
pub mod config;
pub mod core;
pub mod detectors;
pub mod formatters;
pub mod generators;
pub mod models;
pub mod parsers;
pub mod runtime;
pub mod utils;

/// Re-export commands for use in main.rs
pub use commands::*;

/// The current version of the crate.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
