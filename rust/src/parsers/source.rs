use camino::Utf8Path;
use regex::Regex;
use crate::models::{EnvironmentFile, EnvironmentVariable, FileFormat, Origin, OriginFormat, OriginKind};
use crate::parsers::Parser;

/// Create the source-code parser for a set of file extensions.
///
/// Scans for `process.env.NAME`, `process.env['NAME']`, and `import.meta.env.NAME`
/// usages. Comments and string literals are stripped first (a state machine that
/// understands quotes, escape sequences, template literals, and `${...}`
/// interpolation) so documented/string occurrences don't create false positives.
pub struct SourceParser {
    ext_set: std::collections::HashSet<String>,
}

impl SourceParser {
    pub fn new(extensions: Vec<String>) -> Self {
        let ext_set = extensions
            .iter()
            .map(|e| e.strip_prefix('.').unwrap_or(e).to_lowercase())
            .collect();
        Self { ext_set }
    }
}

impl Parser for SourceParser {
    fn id(&self) -> &'static str {
        "source"
    }

    fn match_path(&self, file_path: &Utf8Path) -> bool {
        let ext = file_path.extension().unwrap_or("").to_lowercase();
        self.ext_set.contains(&ext)
    }

    fn parse(&self, content: &str, file_path: &Utf8Path) -> EnvironmentFile {
        let stripped = strip_comments(content);
        let mut usages = Vec::new();

        let patterns = [
            Regex::new(r"\bprocess\.env\.([A-Za-z_$][\w$]*)").unwrap(),
            Regex::new(r#"\bprocess\.env\[['"]([A-Za-z_$][\w$]*)['"]\]"#).unwrap(),
            Regex::new(r"\bimport\.meta\.env\.([A-Za-z_$][\w$]*)").unwrap(),
        ];

        for re in &patterns {
            for mat in re.find_iter(&stripped) {
                if let Some(caps) = re.captures(mat.as_str()) {
                    if let Some(name) = caps.get(1).map(|m| m.as_str().to_string()) {
                        let origin = Origin {
                            file_path: file_path.to_path_buf(),
                            line: Some(line_number_at(&stripped, mat.start())),
                            kind: OriginKind::Usage,
                            environment: None,
                            format: Some(OriginFormat::Source),
                            subkind: None,
                        };
                        usages.push(EnvironmentVariable::create(name, None, vec![origin], None));
                    }
                }
            }
        }

        EnvironmentFile {
            file_path: file_path.to_path_buf(),
            format: FileFormat::Source,
            environment: None,
            variables: vec![],
            usages: EnvironmentVariable::merge(usages),
        }
    }
}

/// 1-based line number for a character offset in `text`.
fn line_number_at(text: &str, offset: usize) -> usize {
    text[..offset.min(text.len())].chars().filter(|&c| c == '\n').count() + 1
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Code,
    CodeTpl,
    Sq,
    Dq,
    Tq,
}

struct Frame {
    mode: Mode,
    /// Brace depth for `${...}` interpolation inside a template literal.
    tpl_depth: usize,
    /**
     * For string frames: when true, the string content is preserved verbatim
     * (used for computed-property access like `process.env["KEY"]` where the
     * string is a variable name, not a literal we want to blank out).
     */
    preserve: bool,
}

/// Replace comments and string-literal *contents* with spaces while preserving
/// line structure (newlines and everything else are kept in position).
/// Template-literal `${...}` interpolation is treated as code so
/// `process.env.X` inside it is still found. This makes the later regex scan
/// immune to comments and strings without needing a full JS parser.
fn strip_comments(code: &str) -> String {
    let mut out = String::new();
    let chars: Vec<char> = code.chars().collect();
    let len = chars.len();
    let mut i = 0;
    let mut stack: Vec<Frame> = vec![Frame { mode: Mode::Code, tpl_depth: 0, preserve: false }];

    let skip_line_comment = |i: &mut usize, out: &mut String| {
        while *i < len && chars[*i] != '\n' {
            out.push(' ');
            *i += 1;
        }
    };

    let skip_block_comment = |i: &mut usize, out: &mut String| {
        out.push_str("  ");
        *i += 2;
        while *i < len {
            if chars[*i] == '*' && *i + 1 < len && chars[*i + 1] == '/' {
                out.push_str("  ");
                *i += 2;
                return;
            }
            if chars[*i] == '\n' {
                out.push('\n');
            } else {
                out.push(' ');
            }
            *i += 1;
        }
    };

    while i < len {
        let c = chars[i];
        let next = if i + 1 < len { Some(chars[i + 1]) } else { None };

        // Get current mode by directly accessing stack.last()
        let mode = stack.last().unwrap().mode;

        match mode {
            Mode::Code | Mode::CodeTpl => {
                if c == '\'' || c == '"' || c == '`' {
                    let string_mode = match c {
                        '`' => Mode::Tq,
                        '"' => Mode::Dq,
                        _ => Mode::Sq,
                    };
                    // A string that immediately follows `[` is a computed-property key
                    let preserve = c != '`' && i > 0 && chars[i - 1] == '[';
                    stack.push(Frame { mode: string_mode, tpl_depth: 0, preserve });
                    out.push(c);
                    i += 1;
                } else if c == '/' && next == Some('/') {
                    skip_line_comment(&mut i, &mut out);
                } else if c == '/' && next == Some('*') {
                    skip_block_comment(&mut i, &mut out);
                } else if mode == Mode::CodeTpl {
                    if c == '{' {
                        stack.last_mut().unwrap().tpl_depth += 1;
                    } else if c == '}' {
                        stack.last_mut().unwrap().tpl_depth -= 1;
                        if stack.last().unwrap().tpl_depth == 0 {
                            stack.pop();
                        }
                    }
                    out.push(c);
                    i += 1;
                } else {
                    out.push(c);
                    i += 1;
                }
            }
            Mode::Tq => {
                if c == '\\' && i + 1 < len {
                    out.push(c);
                    out.push(chars[i + 1]);
                    i += 2;
                } else if c == '`' {
                    stack.pop();
                    out.push(c);
                    i += 1;
                } else if c == '$' && next == Some('{') {
                    out.push_str("${");
                    i += 2;
                    stack.push(Frame { mode: Mode::CodeTpl, tpl_depth: 1, preserve: false });
                } else {
                    // Template-literal content (not in interpolation) is blanked
                    out.push(' ');
                    i += 1;
                }
            }
            Mode::Sq | Mode::Dq => {
                let quote = if mode == Mode::Sq { '\'' } else { '"' };
                let preserve = stack.last().unwrap().preserve;
                if c == '\\' && i + 1 < len {
                    if preserve {
                        out.push(c);
                        out.push(chars[i + 1]);
                    } else {
                        out.push_str("  ");
                    }
                    i += 2;
                } else if c == quote {
                    out.push(c);
                    i += 1;
                    stack.pop();
                } else if preserve {
                    // Preserve computed-property key content verbatim.
                    out.push(c);
                    i += 1;
                } else {
                    // Regular string literal content — blank it out.
                    out.push(' ');
                    i += 1;
                }
            }
        }
    }

    out
}