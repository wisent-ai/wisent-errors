//! What every Wisent CLI prints and reads: a JSON document, or with `--text`
//! the same document as one `path: value` line per field (cli.md rule 13),
//! and JSON input files read with the path named in every refusal.
//!
//! Four CLIs carried their own copies of these three functions; a change to
//! the output contract had to be made four times and the copies drifted.
//! Behind the `cli-output` feature so the envelope stays dependency-free for
//! everyone else. Every refusal is a declared cause of
//! `wisent_errors.cli_output.read_json` or `wisent_errors.cli_output.print`
//! ([`crate::failures`]).

use std::fmt;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::error::Category;
use serde_json::Value;

use crate::failures as own;
use crate::render::escape;
use crate::Cause;

/// An input file that could not be read or is not the JSON it should be,
/// with what the reader found when it refused.
#[derive(Debug)]
pub enum ReadJsonError {
    Read {
        path: PathBuf,
        source: io::Error,
        /// What is at the path: its kind, size and permissions, or the
        /// directory that should hold it.
        state: String,
        directory: bool,
    },
    Parse {
        path: PathBuf,
        source: serde_json::Error,
        /// The type the file was decoded as.
        expected: &'static str,
        bytes: usize,
        /// The line the decoder stopped at, as the file holds it.
        line_text: String,
    },
}

/// What is at `path`, for a refusal to show: the file's kind, size and
/// permissions, or, when nothing is there, what the directory meant to hold
/// it holds.
fn state_of(path: &Path) -> String {
    match std::fs::metadata(path) {
        Ok(found) => {
            let kind = if found.is_dir() {
                "a directory".to_owned()
            } else {
                format!("a file of {} bytes", found.len())
            };
            let access = if found.permissions().readonly() { "read-only" } else { "writable" };
            format!("{} is {kind}, {access}", path.display())
        }
        Err(missing) => {
            let parent = match path.parent() {
                Some(parent) if !parent.as_os_str().is_empty() => parent,
                _ => Path::new("."),
            };
            match std::fs::read_dir(parent) {
                Ok(entries) => format!(
                    "{} cannot be examined ({missing}); {} exists and holds {} entries",
                    path.display(),
                    parent.display(),
                    entries.count()
                ),
                Err(error) => format!(
                    "{} cannot be examined ({missing}), and {} cannot be listed either: {error}",
                    path.display(),
                    parent.display()
                ),
            }
        }
    }
}

impl ReadJsonError {
    /// The declared cause this refusal is.
    pub fn cause(&self) -> &'static Cause {
        match self {
            Self::Read { directory: true, .. } => &own::CLI_OUTPUT_READ_JSON_INPUT_IS_DIRECTORY,
            Self::Read { source, .. } => match source.kind() {
                io::ErrorKind::NotFound => &own::CLI_OUTPUT_READ_JSON_INPUT_ABSENT,
                io::ErrorKind::PermissionDenied => &own::CLI_OUTPUT_READ_JSON_INPUT_NOT_PERMITTED,
                _ => &own::CLI_OUTPUT_READ_JSON_INPUT_READ_INTERRUPTED,
            },
            Self::Parse { source, .. } => match source.classify() {
                Category::Eof => &own::CLI_OUTPUT_READ_JSON_INPUT_TRUNCATED,
                Category::Data => &own::CLI_OUTPUT_READ_JSON_INPUT_WRONG_SHAPE,
                Category::Syntax | Category::Io => &own::CLI_OUTPUT_READ_JSON_INPUT_NOT_JSON,
            },
        }
    }

    /// The values the cause's sentences name.
    pub fn values(&self) -> Vec<(&'static str, String)> {
        match self {
            Self::Read { path, source, state, .. } => vec![
                ("path", path.display().to_string()),
                ("error", source.to_string()),
                ("kind", format!("{:?}", source.kind())),
                ("state", state.clone()),
                ("parent", state.clone()),
                (
                    "cwd",
                    std::env::current_dir().map_or_else(|error| format!("a working directory that cannot be read ({error})"), |dir| dir.display().to_string()),
                ),
            ],
            Self::Parse { path, source, expected, bytes, line_text } => vec![
                ("path", path.display().to_string()),
                ("error", source.to_string()),
                ("expected", (*expected).to_owned()),
                ("bytes", bytes.to_string()),
                ("line", source.line().to_string()),
                ("column", source.column().to_string()),
                ("quoted_line", escape(line_text)),
            ],
        }
    }
}

impl fmt::Display for ReadJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let values = self.values();
        let borrowed: Vec<(&str, &str)> = values.iter().map(|(key, value)| (*key, value.as_str())).collect();
        formatter.write_str(&self.cause().refusal(&borrowed))
    }
}

impl std::error::Error for ReadJsonError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            ReadJsonError::Read { source, .. } => Some(source),
            ReadJsonError::Parse { source, .. } => Some(source),
        }
    }
}

/// Read and decode one JSON file. The refusal names the file, what is at
/// it, and where in it the decoder stopped.
pub fn read_json<T: DeserializeOwned>(path: impl AsRef<Path>) -> Result<T, ReadJsonError> {
    let path = path.as_ref();
    let input = std::fs::read(path).map_err(|source| ReadJsonError::Read {
        path: path.to_path_buf(),
        state: state_of(path),
        directory: path.is_dir(),
        source,
    })?;
    serde_json::from_slice(&input).map_err(|source| {
        // A line past the end of the file is what an empty input reports,
        // and it shows as an empty line.
        let line_text = String::from_utf8_lossy(&input)
            .lines()
            .nth(source.line().saturating_sub(1))
            .map_or_else(String::new, |line| line.chars().take(120).collect());
        ReadJsonError::Parse {
            path: path.to_path_buf(),
            expected: std::any::type_name::<T>(),
            bytes: input.len(),
            line_text,
            source,
        }
    })
}

/// A declared cause of printing, as the serde_json error the caller's error
/// type already converts from, its message the declared refusal.
fn print_refusal(cause: &Cause, kind: io::ErrorKind, values: &[(&str, &str)]) -> serde_json::Error {
    serde_json::Error::io(io::Error::new(kind, cause.refusal(values)))
}

/// Print `value` as pretty JSON, or with `text` as one `path: value` line
/// per field, from the same document. A refusal is a declared cause of
/// `wisent_errors.cli_output.print`.
pub fn output<T: Serialize, E: From<serde_json::Error>>(value: &T, text: bool) -> Result<(), E> {
    let type_name = std::any::type_name::<T>();
    let unrepresentable = |error: serde_json::Error| {
        let shown = error.to_string();
        print_refusal(
            &own::CLI_OUTPUT_PRINT_DOCUMENT_UNREPRESENTABLE,
            io::ErrorKind::InvalidData,
            &[("type", type_name), ("error", &shown)],
        )
    };
    let document = serde_json::to_value(value).map_err(unrepresentable)?;
    let body = if text {
        let mut lines = Vec::new();
        text_lines(&document, String::new(), &mut lines);
        lines.join("\n")
    } else {
        serde_json::to_string_pretty(&document).map_err(unrepresentable)?
    };
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "{body}").and_then(|()| stdout.flush()).map_err(|error| {
        let (bytes, kind, shown) = ((body.len() + 1).to_string(), format!("{:?}", error.kind()), error.to_string());
        let cause = if error.kind() == io::ErrorKind::BrokenPipe {
            &own::CLI_OUTPUT_PRINT_OUTPUT_CLOSED
        } else {
            &own::CLI_OUTPUT_PRINT_OUTPUT_UNWRITABLE
        };
        print_refusal(cause, error.kind(), &[("bytes", &bytes), ("kind", &kind), ("error", &shown)])
    })?;
    Ok(())
}

/// One `path: value` line per leaf of `node`: object keys joined with `.`,
/// array items as `[index]`, strings unquoted, and `-` for null and for an
/// empty array or object.
pub fn text_lines(node: &Value, path: String, lines: &mut Vec<String>) {
    let child = |key: &str| {
        if path.is_empty() {
            key.to_owned()
        } else {
            format!("{path}.{key}")
        }
    };
    match node {
        Value::Array(items) if !items.is_empty() => {
            for (index, item) in items.iter().enumerate() {
                text_lines(item, format!("{path}[{index}]"), lines);
            }
        }
        Value::Object(fields) if !fields.is_empty() => {
            for (key, item) in fields {
                text_lines(item, child(key), lines);
            }
        }
        Value::String(value) => lines.push(format!("{path}: {value}")),
        Value::Null | Value::Array(_) | Value::Object(_) => lines.push(format!("{path}: -")),
        other => lines.push(format!("{path}: {other}")),
    }
}
