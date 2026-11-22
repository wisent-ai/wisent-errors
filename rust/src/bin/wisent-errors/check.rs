//! The checks a product's CI runs on what its own commands print:
//! `doctor check <errors-list.json> <doctor.json>` holds the findings
//! `<product> doctor --json` printed to the functionalities `<product>
//! errors list --json` declares (`diagnosis::problems`: a functionality with
//! an entry point and no check, one checked twice, a check of one the
//! catalogue does not declare), and `warnings check <warnings-list.json>`
//! holds each warning `<product> warnings list` printed to the declaration
//! rules of the Rust runtime (`Operation::warning_problems`, the hazard read
//! with `Hazard::parse`). A file that cannot be read is
//! `wisent_errors.cli_output.read_json`'s refusal; one that is not what its
//! command prints, and the problems found, are the causes of
//! `wisent_errors.command.check`.

use std::process::ExitCode;

use serde_json::{json, Value};
use wisent_errors::cli_output::read_json;
use wisent_errors::declaration as rules;
use wisent_errors::diagnosis::{self, Check, Probe};
use wisent_errors::failures as own;
use wisent_errors::operation::fill;
use wisent_errors::{Hazard, Operation, Warning};

use crate::arguments::quoted;
use crate::product::described;
use crate::say;

/// `text` for as long as the process runs. An `Operation` and a `Warning`
/// hold `'static` text, as a product declares them in code; this one-shot
/// command reads each declaration from a file once and ends.
fn leak(text: &str) -> &'static str {
    String::leak(text.to_owned())
}

/// A functionality read from a listing, with only what the checks read.
fn declared(id: &str, entries: Vec<&'static str>, warnings: Vec<&'static Warning>) -> Operation {
    Operation { id: leak(id), entries: entries.leak(), uses: &[], summary: "", docs: "", causes: &[], warnings: warnings.leak() }
}

/// Each problem, numbered, on the one line a refusal is.
fn numbered(problems: &[String]) -> String {
    problems
        .iter()
        .enumerate()
        .map(|(index, problem)| format!("({}) {problem}", index + 1))
        .collect::<Vec<_>>()
        .join(" ")
}

/// One input file: what it is, where it is, and the command that prints it.
struct Input<'a> {
    what: &'static str,
    path: &'a str,
    source: &'static str,
}

impl Input<'_> {
    /// The file, read as JSON, or `read_json`'s refusal of it.
    fn read(&self) -> Result<Value, ExitCode> {
        read_json::<Value>(self.path)
            .map_err(|refused| say::refuse_owned(&own::CLI_OUTPUT_READ_JSON, refused.cause(), &refused.values()))
    }

    /// The refusal of `place`, which holds `found` and is not `wanted`.
    fn refuse(&self, place: &str, wanted: &str, found: Option<&Value>) -> ExitCode {
        say::refuse(
            &own::COMMAND_CHECK,
            &own::COMMAND_CHECK_INPUT_SHAPE_INVALID,
            &[("what", self.what), ("path", self.path), ("place", place), ("wanted", wanted), ("found", &described(found)), ("source", self.source)],
        )
    }

    /// The list the document is, or holds under `operations`.
    fn list<'v>(&self, document: &'v Value, wanted: &str) -> Result<&'v [Value], ExitCode> {
        match document {
            Value::Array(items) => Ok(items),
            Value::Object(fields) => match fields.get("operations") {
                Some(Value::Array(items)) => Ok(items),
                _ => Err(self.refuse("the document", wanted, Some(document))),
            },
            _ => Err(self.refuse("the document", wanted, Some(document))),
        }
    }

    /// `item`, which must be an object.
    fn object<'v>(&self, item: &'v Value, place: &str, wanted: &str) -> Result<&'v Value, ExitCode> {
        match item {
            Value::Object(_) => Ok(item),
            _ => Err(self.refuse(place, wanted, Some(item))),
        }
    }

    /// The text `item` holds under `key`.
    fn text<'v>(&self, item: &'v Value, place: &str, key: &str) -> Result<&'v str, ExitCode> {
        match item.get(key) {
            Some(Value::String(text)) => Ok(text),
            found => Err(self.refuse(&format!("{place}'s \"{key}\""), "a text", found)),
        }
    }
}

/// `doctor check <errors-list.json> <doctor.json>`.
pub fn doctor(listing_path: &str, findings_path: &str, text: bool) -> ExitCode {
    let listing = Input { what: "the failure catalogue", path: listing_path, source: "`<product> errors list --json`" };
    let findings = Input { what: "the doctor's findings", path: findings_path, source: "`<product> doctor --json`" };
    match doctor_held(&listing, &findings, text) {
        Ok(status) | Err(status) => status,
    }
}

fn doctor_held(listing: &Input, findings: &Input, text: bool) -> Result<ExitCode, ExitCode> {
    let functionality = "an object with its \"operation\" and its \"entries\"";
    let document = listing.read()?;
    let mut built = Vec::new();
    for (index, item) in listing.list(&document, "a list of functionalities as `errors list --json` prints them")?.iter().enumerate() {
        let place = format!("functionality {}", index + 1);
        let item = listing.object(item, &place, functionality)?;
        let id = listing.text(item, &place, "operation")?;
        let found = item.get("entries");
        let entries: Option<Vec<&'static str>> = match found {
            Some(Value::Array(entries)) => entries.iter().map(|entry| entry.as_str().map(leak)).collect(),
            _ => None,
        };
        let Some(entries) = entries else {
            return Err(listing.refuse(&format!("{place} ({id})'s \"entries\""), "a list of the texts that start it", found));
        };
        built.push(declared(id, entries, Vec::new()));
    }
    let catalogue: &'static [Operation] = built.leak();
    let operations: Vec<&'static Operation> = catalogue.iter().collect();

    let document = findings.read()?;
    let mut checked = Vec::new();
    for (index, item) in findings.list(&document, "the list of findings `doctor --json` prints")?.iter().enumerate() {
        let place = format!("finding {}", index + 1);
        let item = findings.object(item, &place, "an object naming its \"operation\"")?;
        checked.push(findings.text(item, &place, "operation")?);
    }
    // A finding of a functionality the catalogue does not declare is held to
    // it as a check of one it does not list.
    let undeclared: &'static [Operation] = checked
        .iter()
        .filter(|id| !operations.iter().any(|operation| operation.id == **id))
        .map(|id| declared(id, Vec::new(), Vec::new()))
        .collect::<Vec<_>>()
        .leak();
    let checks: Vec<Check> = checked
        .iter()
        .filter_map(|id| operations.iter().copied().chain(undeclared).find(|operation| operation.id == *id))
        .map(|operation| Check { operation, probe: Probe::Skipped("read from the doctor's findings") })
        .collect();
    let problems = diagnosis::problems(&operations, &checks);
    let started = operations.iter().filter(|operation| !operation.entries.is_empty()).count();
    if problems.is_empty() {
        return Ok(say::print(&json!({ "functionalities": operations.len(), "with_entry_points": started, "findings": checked.len() }), text));
    }
    let (count, problems, started, reported) = (problems.len().to_string(), numbered(&problems), started.to_string(), checked.len().to_string());
    Err(say::refuse(
        &own::COMMAND_CHECK,
        &own::COMMAND_CHECK_DOCTOR_INCOMPLETE,
        &[
            ("doctor", findings.path),
            ("listing", listing.path),
            ("count", &count),
            ("problems", &problems),
            ("declared", &started),
            ("findings", &reported),
        ],
    ))
}

/// `warnings check <warnings-list.json>`.
pub fn warnings(path: &str, text: bool) -> ExitCode {
    let listing = Input { what: "the warnings listing", path, source: "`<product> warnings list`" };
    match warnings_held(&listing, text) {
        Ok(status) | Err(status) => status,
    }
}

fn warnings_held(listing: &Input, text: bool) -> Result<ExitCode, ExitCode> {
    let fields = "an object with its id, hazard, effect, consequence, safeguard, confirm and test";
    let hazards = Hazard::ALL.iter().map(|hazard| hazard.as_str()).collect::<Vec<_>>().join(", ");
    let document = listing.read()?;
    let items = listing.list(&document, "a list of functionalities as `warnings list` prints them")?;
    let mut problems = Vec::new();
    let mut read = 0;
    for (index, item) in items.iter().enumerate() {
        let place = format!("functionality {}", index + 1);
        let item = listing.object(item, &place, "an object with its \"operation\" and its \"warnings\"")?;
        let id = listing.text(item, &place, "operation")?;
        let place = format!("{place} ({id})");
        let found = item.get("warnings");
        let Some(Value::Array(listed)) = found else {
            return Err(listing.refuse(&format!("{place}'s \"warnings\""), "a list of its warnings", found));
        };
        let mut built = Vec::new();
        for (position, warning) in listed.iter().enumerate() {
            let at = format!("{place}'s warning {}", position + 1);
            let warning = listing.object(warning, &at, fields)?;
            let field = |key: &str| listing.text(warning, &at, key);
            let (warning_id, hazard) = (field("id")?, field("hazard")?);
            let hazard = match Hazard::parse(hazard) {
                Some(parsed) => parsed,
                None => {
                    let quoted_hazard = quoted(hazard);
                    let named = fill(rules::HAZARD_UNKNOWN, &[("id", warning_id), ("quoted_hazard", &quoted_hazard), ("hazards", &hazards)]);
                    problems.push(format!("operation {id}: {named}"));
                    // The rest of the warning is still held to its rules;
                    // the hazard it stands under here is never printed.
                    Hazard::Irreversible
                }
            };
            built.push(Warning {
                id: leak(warning_id),
                hazard,
                effect: leak(field("effect")?),
                consequence: leak(field("consequence")?),
                safeguard: leak(field("safeguard")?),
                confirm: leak(field("confirm")?),
                test: leak(field("test")?),
            });
        }
        read += built.len();
        let warnings: &'static [Warning] = built.leak();
        problems.extend(declared(id, Vec::new(), warnings.iter().collect()).warning_problems());
    }
    if problems.is_empty() {
        return Ok(say::print(&json!({ "functionalities": items.len(), "warnings": read }), text));
    }
    let (count, problems, warnings, operations) = (problems.len().to_string(), numbered(&problems), read.to_string(), items.len().to_string());
    Err(say::refuse(
        &own::COMMAND_CHECK,
        &own::COMMAND_CHECK_WARNINGS_INVALID,
        &[("listing", listing.path), ("count", &count), ("problems", &problems), ("warnings", &warnings), ("operations", &operations)],
    ))
}
