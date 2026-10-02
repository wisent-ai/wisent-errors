//! What every Wisent CLI prints and reads: a JSON document, or with `--text`
//! the same document as one `path: value` line per field (cli.md rule 13),
//! and JSON input files read with the path named in every refusal.
//!
//! Four CLIs carried their own copies of these three functions; a change to
//! the output contract had to be made four times and the copies drifted.
//! Behind the `cli-output` feature so the envelope stays dependency-free for
//! everyone else.

use std::fmt;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;

/// An input file that could not be read or is not the JSON it should be.
#[derive(Debug)]
pub enum ReadJsonError {
    Read { path: PathBuf, source: std::io::Error },
    Parse { path: PathBuf, source: serde_json::Error },
}

impl fmt::Display for ReadJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ReadJsonError::Read { path, .. } => write!(formatter, "failed to read {}", path.display()),
            ReadJsonError::Parse { path, .. } => write!(formatter, "invalid JSON in {}", path.display()),
        }
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

/// Read and decode one JSON file. The refusal names the file; the cause
/// says what the filesystem or the decoder answered.
pub fn read_json<T: DeserializeOwned>(path: impl AsRef<Path>) -> Result<T, ReadJsonError> {
    let path = path.as_ref();
    let input = std::fs::read(path).map_err(|source| ReadJsonError::Read {
        path: path.to_path_buf(),
        source,
    })?;
    serde_json::from_slice(&input).map_err(|source| ReadJsonError::Parse {
        path: path.to_path_buf(),
        source,
    })
}

/// Print `value` as pretty JSON, or with `text` as one `path: value` line
/// per field, from the same document.
pub fn output<T: Serialize, E: From<serde_json::Error>>(value: &T, text: bool) -> Result<(), E> {
    let document = serde_json::to_value(value)?;
    if !text {
        println!("{}", serde_json::to_string_pretty(&document)?);
        return Ok(());
    }
    let mut lines = Vec::new();
    text_lines(&document, String::new(), &mut lines);
    println!("{}", lines.join("\n"));
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
