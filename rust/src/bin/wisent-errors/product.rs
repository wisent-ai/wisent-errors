//! The product a telemetry, support or doctor command speaks for, read from
//! the file `--product` names: a JSON object with the product's `id` (the
//! name of its own command, under which its telemetry is kept), the
//! `app_id` the collector declares for this surface of it, the `version`
//! this copy reports and, when the product sends its queue in the
//! background as each reported command ends, `flush`: the words of the
//! command that sends it, its program first. A product written in any
//! language names its file; the refusals are the declared causes of
//! `wisent_errors.command.product` and, for the file itself, of
//! `wisent_errors.cli_output.read_json`.

use std::process::ExitCode;
use std::sync::OnceLock;

use serde_json::{Map, Value};
use wisent_errors::cli_output::read_json;
use wisent_errors::failures as own;
use wisent_errors::telemetry::Product;

use crate::arguments::{quoted, Line};
use crate::say;

const EXAMPLE: &str = r#"{"id": "example-product", "app_id": "example-product-cli", "version": "1.0.0", "flush": ["example-product", "telemetry", "flush"]}"#;
const WORDS: &str = "lowercase words joined by '-'";
const VERSION: &str = "a version written as text";
const FLUSH: &str = "a list of the words of the command that sends the queue, its program first, each a text that is not empty";

/// What a field holds, as a refusal shows it; also what `doctor check` and
/// `warnings check` found where they read a field.
pub(crate) fn described(value: Option<&Value>) -> String {
    match value {
        None => "nothing, as the file has no such key".to_owned(),
        Some(Value::String(text)) => format!("the text {}", quoted(text)),
        Some(Value::Null) => "null".to_owned(),
        Some(Value::Bool(flag)) => format!("the boolean {flag}"),
        Some(Value::Number(number)) => format!("the number {number}"),
        Some(list @ Value::Array(_)) => format!("the list {list}"),
        Some(object @ Value::Object(_)) => format!("the object {object}"),
    }
}

/// `lowercase words joined by '-'`, each a lowercase letter, then lowercase
/// letters and digits.
fn named(text: &str) -> bool {
    text.split('-').all(|word| {
        word.starts_with(|first: char| first.is_ascii_lowercase())
            && word.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
    })
}

/// The text of `field`, or its declared refusal.
fn field(read: &Map<String, Value>, path: &str, name: &str, wanted: &str, valid: fn(&str) -> bool) -> Result<String, ExitCode> {
    match read.get(name) {
        Some(Value::String(text)) if valid(text) => Ok(text.clone()),
        found => Err(say::refuse(
            &own::COMMAND_PRODUCT,
            &own::COMMAND_PRODUCT_PRODUCT_FIELD_INVALID,
            &[("path", path), ("field", name), ("wanted", wanted), ("found", &described(found)), ("example", EXAMPLE)],
        )),
    }
}

/// The words of the command that sends the queue, when the file names one.
fn flush_words(read: &Map<String, Value>, path: &str) -> Result<Option<Vec<String>>, ExitCode> {
    let found = read.get("flush");
    let words: Option<Vec<String>> = match found {
        None => return Ok(None),
        Some(Value::Array(items)) if !items.is_empty() => items
            .iter()
            .map(|item| item.as_str().filter(|word| !word.is_empty()).map(str::to_owned))
            .collect(),
        Some(_) => None,
    };
    match words {
        Some(words) => Ok(Some(words)),
        None => Err(say::refuse(
            &own::COMMAND_PRODUCT,
            &own::COMMAND_PRODUCT_PRODUCT_FIELD_INVALID,
            &[("path", path), ("field", "flush"), ("wanted", FLUSH), ("found", &described(found)), ("example", EXAMPLE)],
        )),
    }
}

/// The id, app id and version the product file named, kept for the whole
/// run, since `Product` borrows them for as long as the process lives.
static NAMED: OnceLock<[String; 3]> = OnceLock::new();

/// What the product file names.
pub struct Named {
    pub product: Product,
    /// The file it was read from, as `--product` named it.
    pub path: String,
    /// The command that sends the queue in the background, program first.
    pub flush: Option<Vec<String>>,
}

/// The product `line` names, read from its file.
pub fn read(line: &Line) -> Result<Named, ExitCode> {
    let Some(path) = line.product.clone() else {
        return Err(say::refuse(
            &own::COMMAND_PRODUCT,
            &own::COMMAND_PRODUCT_PRODUCT_UNNAMED,
            &[("command", &line.command()), ("quoted_arguments", &quoted(&line.arguments))],
        ));
    };
    let read: Map<String, Value> = read_json(&path).map_err(|refused| {
        say::refuse_owned(&own::CLI_OUTPUT_READ_JSON, refused.cause(), &refused.values())
    })?;
    let fields = [
        field(&read, &path, "id", WORDS, named)?,
        field(&read, &path, "app_id", WORDS, named)?,
        field(&read, &path, "version", VERSION, |text| !text.trim().is_empty())?,
    ];
    let flush = flush_words(&read, &path)?;
    let [id, app_id, version] = NAMED.get_or_init(|| fields);
    Ok(Named { product: Product { id, app_id, version }, path, flush })
}
