//! Emit every golden case through the Rust runtime, one JSON per line.
//!
//! The three emitters exist so the conformance harness can compare languages
//! against each other and against the golden field, rather than each runtime
//! asserting its own behaviour and agreeing with nobody.
//!
//! Cases are tab separated `key=value` for exactly this reason: the crate
//! carries no JSON parser, because a package every product has to adopt must be
//! cheap to adopt.

use std::collections::BTreeMap;
use std::io::{self, Read};

use wisent_errors::{Code, Failure};

/// The first `=` separates, so a value may contain more of them.
fn parse_case(line: &str) -> BTreeMap<&str, &str> {
    let mut fields = BTreeMap::new();
    for pair in line.split('\t') {
        if let Some((key, value)) = pair.split_once('=') {
            fields.insert(key, value);
        }
    }
    fields
}

fn required<'a>(fields: &BTreeMap<&'a str, &'a str>, key: &str, name: &str) -> &'a str {
    match fields.get(key) {
        Some(value) => value,
        None => {
            eprintln!("{name}: case is missing {key}");
            std::process::exit(1);
        }
    }
}

fn code_or_exit(text: &str, name: &str) -> Code {
    match Code::parse(text) {
        Some(code) => code,
        None => {
            eprintln!("{name}: unknown code {text:?}");
            std::process::exit(1);
        }
    }
}

fn main() {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        eprintln!("could not read the case file on stdin");
        std::process::exit(1);
    }

    for line in input.lines() {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let fields = parse_case(line);
        let name = required(&fields, "name", "case");

        let mut envelope = match Failure::new(
            required(&fields, "failure_point", name),
            code_or_exit(required(&fields, "code", name), name),
            required(&fields, "service", name),
            required(&fields, "impact", name),
            required(&fields, "detail", name),
        ) {
            Ok(envelope) => envelope,
            Err(error) => {
                eprintln!("{name}: {error}");
                std::process::exit(1);
            }
        };

        if let Some(point) = fields.get("cause_failure_point") {
            let cause = match Failure::new(
                *point,
                code_or_exit(required(&fields, "cause_code", name), name),
                required(&fields, "cause_service", name),
                required(&fields, "cause_impact", name),
                required(&fields, "cause_detail", name),
            ) {
                Ok(cause) => cause,
                Err(error) => {
                    eprintln!("{name}: cause {error}");
                    std::process::exit(1);
                }
            };
            envelope = envelope.caused_by(cause);
        }

        if let Some(context) = fields.get("context") {
            match context.split_once('=') {
                Some((key, value)) => envelope = envelope.with_context(key, value),
                None => {
                    eprintln!("{name}: context {context:?} is not key=value");
                    std::process::exit(1);
                }
            }
        }

        println!("{name}\t{}", envelope.to_json());
    }
}
