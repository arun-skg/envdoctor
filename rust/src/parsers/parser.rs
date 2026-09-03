use crate::models::EnvironmentFile;

/// A parser turns the raw text of one supported file format into envdoctor's
/// normalized `EnvironmentFile`. Parsers are independent and format-specific:
/// they know nothing about detectors, the audit, or each other.
///
/// `match` decides whether a file path belongs to this format; `parse` handles
/// the content. A parser must never throw on malformed input — it should
/// produce whatever it can and let the caller report parse errors.
pub trait Parser: Send + Sync {
    fn id(&self) -> &'static str;
    fn match_path(&self, file_path: &camino::Utf8Path) -> bool;
    fn parse(&self, content: &str, file_path: &camino::Utf8Path) -> EnvironmentFile;
}

/// Ordered list of parsers, most specific first.
pub type ParserRegistry = Vec<Box<dyn Parser>>;

/// Match a path against a registry; returns the first parser that claims it.
pub fn parser_for_path<'a>(registry: &'a ParserRegistry, _file_path: &camino::Utf8Path) -> Option<&'a dyn Parser> {
    registry.iter().find(|p| p.match_path(_file_path)).map(|b| b.as_ref())
}