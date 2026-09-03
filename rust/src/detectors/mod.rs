pub mod detector;
pub mod index;
pub mod missing;
pub mod unused;
pub mod undefined_source;
pub mod duplicates;
pub mod environment_diff;
pub mod type_mismatch;
pub mod public_prefix;
pub mod weak_secret;
pub mod typo;
pub mod schema_validation;

pub use detector::{Detector, Definition, IndexedModel, make_finding};
pub(crate) use detector::{def_sort_key, origin_sort_key};
pub use index::build_index;

pub use missing::MissingDetector;
pub use unused::UnusedDetector;
pub use undefined_source::UndefinedSourceDetector;
pub use duplicates::DuplicatesDetector;
pub use environment_diff::EnvironmentDiffDetector;
pub use type_mismatch::TypeMismatchDetector;
pub use public_prefix::PublicPrefixDetector;
pub use weak_secret::WeakSecretDetector;
pub use typo::TypoDetector;
pub use schema_validation::SchemaValidationDetector;