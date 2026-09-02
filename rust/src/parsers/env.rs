use camino::Utf8Path;
use regex::Regex;
use crate::models::{EnvironmentFile, EnvironmentVariable, FileFormat, Origin, OriginFormat, OriginKind};
use crate::parsers::Parser;

/// Parser for dotenv-style files (`.env`, `.env.local`, `.env.production`, ...).
///
/// We hand-roll the tokenizer instead of using `dotenvy` because the audit
/// needs every occurrence of a key (to detect duplicates and to attribute
/// origins with line numbers), while `dotenvy` silently keeps only the
/// last value for a repeated key.
pub struct EnvParser;

impl Parser for EnvParser {
    fn id(&self) -> &'static str {
        "dotenv"
    }

    fn match_path(&self, file_path: &Utf8Path) -> bool {
        let base = file_path.file_name().unwrap_or("");
        Regex::new(r"^\.env(\..+)?$").unwrap().is_match(base)
    }

    fn parse(&self, content: &str, file_path: &Utf8Path) -> EnvironmentFile {
        let environment = environment_label_for_dotenv(file_path);
        let entries = parse_dotenv(content);
        let entries = apply_ignore_directives(entries, parse_ignore_directives(content));

        let mut variables = Vec::new();
        for entry in entries {
            let origin = Origin {
                file_path: file_path.to_path_buf(),
                line: Some(entry.line),
                kind: OriginKind::Definition,
                environment: Some(environment.clone()),
                format: Some(OriginFormat::Dotenv),
                subkind: None,
            };
            variables.push(EnvironmentVariable::create(
                entry.key,
                Some(entry.value),
                vec![origin],
                entry.ignore_rules,
            ));
        }

        EnvironmentFile {
            file_path: file_path.to_path_buf(),
            format: FileFormat::Dotenv,
            environment: Some(environment),
            variables,
            usages: vec![],
        }
    }
}

/// The environment label derived from a dotenv filename.
pub fn environment_label_for_dotenv(file_path: &Utf8Path) -> String {
    let base = file_path.file_name().unwrap_or("");
    if base == ".env" {
        return "development".to_string();
    }
    if base == ".env.example" {
        return "example".to_string();
    }
    let suffix = base.strip_prefix(".env.").unwrap_or(base.strip_prefix(".env").unwrap_or(""));
    if suffix.is_empty() {
        return "development".to_string();
    }
    // `.env.development.local` → development, `.env.test` → test
    suffix
        .strip_suffix(".local")
        .unwrap_or(suffix)
        .trim_end_matches('.')
        .to_string()
}

#[derive(Debug, Clone)]
struct EnvEntry {
    key: String,
    value: String,
    line: usize,
    ignore_rules: Option<Vec<String>>,
}

#[derive(Debug, Clone)]
struct IgnoreDirective {
    line: usize,
    rules: Vec<String>,
}

/// Parse dotenv content into key/value/line entries.
///
/// Handles: `export ` prefixes, blank lines, full-line comments, inline
/// comments after unquoted values (respecting `\#` escapes), single/double/
/// backtick quoting including multiline quoted values, and the common escape
/// sequences in double-quoted values. Lines without an `=` are ignored,
/// matching `dotenv` behavior.
fn parse_dotenv(content: &str) -> Vec<EnvEntry> {
    let mut entries = Vec::new();
    let chars: Vec<char> = content.chars().collect();
    let len = chars.len();
    let mut i = 0;
    let mut line = 1;

    while i < len {
        // Skip whitespace and blank lines.
        while i < len && chars[i].is_whitespace() {
            if chars[i] == '\n' {
                line += 1;
            }
            i += 1;
        }
        if i >= len {
            break;
        }

        // Full-line comment.
        if chars[i] == '#' {
            while i < len && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }

        // Optional `export` prefix, allowing spaces and tabs between the prefix
        // and the variable name.
        if i + 6 <= len && &chars[i..i+6] == ['e','x','p','o','r','t'] {
            let mut j = i + 6;
            while j < len && (chars[j] == ' ' || chars[j] == '\t') {
                j += 1;
            }
            i = j;
        }

        let start_line = line;

        // Read the key.
        let key_start = i;
        while i < len && (chars[i].is_ascii_alphanumeric() || chars[i] == '_' || chars[i] == '.' || chars[i] == '-') {
            i += 1;
        }
        if i == key_start {
            // No key, skip to end of line
            while i < len && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        let key: String = chars[key_start..i].iter().collect();

        // Skip whitespace before `=`.
        while i < len && chars[i] != '=' && chars[i] != '\n' && chars[i].is_whitespace() {
            i += 1;
        }
        if i >= len || chars[i] != '=' {
            // Malformed line (no `=`); ignore it like dotenv does.
            while i < len && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        i += 1; // consume `=`

        // Skip whitespace before the value.
        while i < len && chars[i] != '\n' && chars[i].is_whitespace() {
            i += 1;
        }

        let value = if i < len && (chars[i] == '"' || chars[i] == '\'' || chars[i] == '`') {
            let quote = chars[i];
            i += 1;
            let mut raw = String::new();
            while i < len {
                let c = chars[i];
                if c == quote {
                    i += 1;
                    break;
                }
                if c == '\\' {
                    if i + 1 < len {
                        let next = chars[i + 1];
                        if quote == '"' && next == 'n' {
                            raw.push('\n');
                            i += 2;
                            continue;
                        }
                        if quote == '"' && next == 't' {
                            raw.push('\t');
                            i += 2;
                            continue;
                        }
                        if quote == '"' && next == 'r' {
                            raw.push('\r');
                            i += 2;
                            continue;
                        }
                        if next == '"' || next == '\'' || next == '`' || next == '\\' {
                            raw.push(next);
                            i += 2;
                            continue;
                        }
                    }
                    raw.push(c);
                    i += 1;
                    continue;
                }
                raw.push(c);
                if c == '\n' {
                    line += 1;
                }
                i += 1;
            }
            raw
        } else {
            // Unquoted value: ends at newline or an unescaped `#`.
            let mut raw = String::new();
            while i < len && chars[i] != '\n' {
                let c = chars[i];
                if c == '\\' && i + 1 < len && chars[i + 1] == '#' {
                    raw.push('#');
                    i += 2;
                    continue;
                }
                if c == '#' {
                    break;
                }
                raw.push(c);
                i += 1;
            }
            raw.trim_end().to_string()
        };

        entries.push(EnvEntry {
            key,
            value,
            line: start_line,
            ignore_rules: None,
        });
    }

    entries
}

/// Parse inline ignore directives placed on the line before a variable
/// definition:
///
///   # envdoctor:ignore unused
///   DEBUG_MODE=true
///
/// Multiple rules can be comma- or space-separated:
///
///   # envdoctor:ignore unused, weak-secret
///   MY_TOKEN=placeholder
fn parse_ignore_directives(content: &str) -> Vec<IgnoreDirective> {
    let mut directives = Vec::new();
    let lines: Vec<&str> = content.split('\n').collect();
    let re = Regex::new(r"(?i)^#\s*envdoctor:ignore\s+([a-z0-9_,\-\s]+)\s*$").unwrap();

    for (idx, line) in lines.iter().enumerate() {
        if let Some(caps) = re.captures(line) {
            if let Some(rules_match) = caps.get(1) {
                let rules: Vec<String> = rules_match
                    .as_str()
                    .split(|c: char| c == ',' || c.is_whitespace())
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                if !rules.is_empty() {
                    directives.push(IgnoreDirective {
                        line: idx + 1,
                        rules,
                    });
                }
            }
        }
    }

    directives
}

/// Attach pending ignore directives to the first entry that appears after them.
fn apply_ignore_directives(mut entries: Vec<EnvEntry>, directives: Vec<IgnoreDirective>) -> Vec<EnvEntry> {
    let entry_by_line: std::collections::HashMap<usize, usize> = entries
        .iter()
        .enumerate()
        .map(|(idx, e)| (e.line, idx))
        .collect();

    let mut pending: Vec<String> = Vec::new();
    let max_line = entries
        .iter()
        .map(|e| e.line)
        .chain(directives.iter().map(|d| d.line))
        .max()
        .unwrap_or(1);

    for line in 1..=max_line {
        if let Some(d) = directives.iter().find(|d| d.line == line) {
            pending.extend(d.rules.clone());
        }
        if let Some(&entry_idx) = entry_by_line.get(&line) {
            if !pending.is_empty() {
                entries[entry_idx].ignore_rules = Some(
                    entries[entry_idx]
                        .ignore_rules
                        .clone()
                        .unwrap_or_default()
                        .into_iter()
                        .chain(pending.drain(..))
                        .collect(),
                );
            }
        }
    }

    entries
}