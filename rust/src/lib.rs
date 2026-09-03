//! envdoctor - Local-first consistency checker for environment variables
//!
//! This is the native Rust port of the TypeScript envdoctor tool.

pub mod models;
pub mod config;
pub mod utils;
pub mod parsers;
pub mod detectors;
pub mod core;
pub mod formatters;
pub mod generators;
pub mod commands;
pub mod runtime;

/// Re-export commands for use in main.rs
pub use commands::*;

/// The current version of the crate.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");