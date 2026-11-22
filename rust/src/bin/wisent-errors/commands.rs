//! What each command does: the telemetry and support commands every product
//! CLI carries from this crate, run for the product the product file names,
//! and the listing of the command's own warnings. docs/command-line.md says
//! each one, what it prints and how it refuses.

use std::path::Path;
use std::process::ExitCode;
use std::time::Duration;

use serde_json::{json, Value};
use wisent_errors::failures as own;
use wisent_errors::telemetry::{Level, Report, Telemetry, EVENTS, QUEUE_DROPPED};
use wisent_errors::{Code, Failure, Operation, Warning};

use crate::arguments::{quoted, Line};
use crate::product::Named;
use crate::say;

/// Every warning of the command's functionalities, each with the one that
/// declares it: turning telemetry off drops what still waits.
static CONSENT_WARNINGS: [&Warning; 1] = [&QUEUE_DROPPED];

/// The functionalities of the command that warn, each with its warnings.
fn warned() -> [Operation; 1] {
    [Operation { warnings: &CONSENT_WARNINGS, ..own::TELEMETRY_CONSENT }]
}

/// `warnings list`: every functionality that warns, as `warnings_json`
/// lists it, each warning linked to its entry on docs/command-line.md.
pub fn warnings_list(text: bool) -> ExitCode {
    let listed: Vec<Value> = warned()
        .iter()
        .map(|operation| {
            serde_json::from_str(&operation.warnings_json(say::WARNINGS_PAGE))
                .expect("Operation::warnings_json writes a JSON document")
        })
        .collect();
    say::print(&Value::Array(listed), text)
}

/// `warnings page`: the section of docs/command-line.md that lists them.
pub fn warnings_page() -> ExitCode {
    let page: Vec<String> = warned().iter().map(Operation::warnings_markdown).collect();
    say::print_text(page.join("\n").trim_end())
}

/// `errors list`: every functionality the command runs and every cause it
/// declares, as `Operation::to_json` lists them, with the exit each cause
/// leaves this command with.
pub fn errors_list(text: bool) -> ExitCode {
    let listed: Vec<Value> = say::catalogue()
        .map(|operation| {
            serde_json::from_str(&operation.to_json(say::EXIT_FAILURE)).expect("Operation::to_json writes a JSON document")
        })
        .collect();
    say::print(&Value::Array(listed), text)
}

/// `errors page`: every functionality the command runs as its page section
/// renders it (`Operation::markdown`, what `stado errors show --markdown`
/// prints for Stado's), each cause under the class its refusal prints.
pub fn errors_page() -> ExitCode {
    let page: Vec<String> = say::catalogue().map(|operation| operation.markdown(say::EXIT_FAILURE)).collect();
    say::print_text(page.join("\n").trim_end())
}

/// `telemetry events`: every event the reporter can send, with the consent it
/// needs and each property it carries.
pub fn events(text: bool) -> ExitCode {
    let listed: Vec<Value> = EVENTS
        .iter()
        .map(|event| {
            json!({
                "name": event.name,
                "consent": event.consent.as_str(),
                "summary": event.summary,
                "properties": event.properties,
            })
        })
        .collect();
    say::print(&Value::Array(listed), text)
}

/// Run a command that speaks for the product the product file named.
pub fn run(line: &Line, named: &Named) -> ExitCode {
    let product = named.product;
    let telemetry = Telemetry::new(product);
    let text = line.text;
    let operand = |index: usize| line.operands[index].as_str();
    match line.spec.words {
        ["telemetry", "status"] => say::print(&telemetry.status(), text),
        ["telemetry", "level"] => match Level::parse(operand(0), product.id) {
            Ok(level) => level_kept(&telemetry, level, line.flag("--yes"), text),
            Err(refused) => say::refuse_failure(&refused),
        },
        ["telemetry", "on"] => level_kept(&telemetry, Level::Errors, false, text),
        ["telemetry", "off"] => level_kept(&telemetry, Level::Off, line.flag("--yes"), text),
        ["telemetry", "failure"] => failure(line, &telemetry, named),
        ["telemetry", "command"] => command(line, &telemetry, named),
        ["telemetry", "help"] => {
            telemetry.help(operand(0));
            say::print(&telemetry.status(), text)
        }
        ["telemetry", "show"] => match telemetry.queued() {
            Ok(queued) => say::print(&Value::Array(queued), text),
            Err(refused) => say::refuse_failure(&refused),
        },
        ["telemetry", "export"] => match telemetry.export(Path::new(operand(0))) {
            Ok(count) => say::print(&json!({ "exported": count, "file": operand(0) }), text),
            Err(refused) => say::refuse_failure(&refused),
        },
        ["telemetry", "flush"] => match telemetry.flush() {
            Ok(delivered) => {
                let printed = say::print(&delivered.to_json(), text);
                match &delivered.stopped {
                    Some(stopped) if printed == ExitCode::SUCCESS => say::refuse_failure(stopped),
                    _ => printed,
                }
            }
            Err(refused) => say::refuse_failure(&refused),
        },
        ["support", "report"] => {
            let report = Report {
                subject: line.value("--subject"),
                // fallback: a report without --description has an empty one, which file_report refuses by name.
                description: line.value("--description").unwrap_or_default(),
                email: line.value("--email"),
                with_failure: line.flag("--with-failure"),
            };
            match telemetry.file_report(&report) {
                Ok(filed) => say::print(&filed, text),
                Err(refused) => say::refuse_failure(&refused),
            }
        }
        ["support", "status"] => match telemetry.reports() {
            Ok(reports) => say::print(&Value::Array(reports), text),
            Err(refused) => say::refuse_failure(&refused),
        },
        _ => unreachable!("every command that speaks for a product is run above: {}", line.command()),
    }
}

/// Keep the user's answer. Turning telemetry off while events wait shows
/// what it drops and does nothing until `--yes` confirms it.
fn level_kept(telemetry: &Telemetry, level: Level, confirmed: bool, text: bool) -> ExitCode {
    if level == Level::Off && !confirmed {
        let queued = match telemetry.queued() {
            Ok(queued) => queued.len(),
            Err(refused) => return say::refuse_failure(&refused),
        };
        if queued > 0 {
            if let Some(directory) = telemetry.directory() {
                let (count, queue) = (queued.to_string(), directory.join("queue").display().to_string());
                let values = [("product", telemetry.product().id), ("queued", count.as_str()), ("queue", queue.as_str())];
                return say::unconfirmed(&own::TELEMETRY_CONSENT, &QUEUE_DROPPED, &values);
            }
        }
    }
    match telemetry.set_level(level) {
        Ok(()) => say::print(&telemetry.status(), text),
        Err(refused) => say::refuse_failure(&refused),
    }
}

/// `telemetry failure <failure-point> <code>`: the failure the product met,
/// queued as the user agreed; a failure of telemetry itself is said on
/// stderr and the command goes on, as it does in every product.
fn failure(line: &Line, telemetry: &Telemetry, named: &Named) -> ExitCode {
    let product = named.product;
    let (point, written) = (line.operands[0].as_str(), line.operands[1].as_str());
    let Some(code) = Code::parse(written) else {
        let codes: Vec<&str> = Code::ALL.iter().map(|code| code.as_str()).collect();
        return say::refuse(
            &own::COMMAND_ARGUMENTS,
            &own::COMMAND_ARGUMENTS_CODE_UNKNOWN,
            &[("point", point), ("quoted_code", &quoted(written)), ("codes", &codes.join(", "))],
        );
    };
    let mut met = match Failure::new(point, code, product.id) {
        Ok(met) => met,
        Err(invalid) => return say::refuse_owned(&own::ENVELOPE_BUILD, invalid.cause(), &invalid.values()),
    };
    if let Some(detail) = line.value("--detail") {
        met = met.detail(detail);
    }
    if let Some(remedy) = line.value("--remedy") {
        met = met.remedy(remedy);
    }
    if let Some(impact) = line.value("--impact") {
        met = met.impact(impact);
    }
    telemetry.failure(&met, line.value("--cause-id"));
    flush_behind(telemetry, named);
    say::print(&telemetry.status(), line.text)
}

/// Start the command the product file names to send the queue, and go on
/// without waiting for it, as a product does when its command ends; one
/// that cannot start is said on stderr and the events wait.
fn flush_behind(telemetry: &Telemetry, named: &Named) {
    let Some((program, arguments)) = named.flush.as_deref().and_then(<[String]>::split_first) else {
        return;
    };
    let arguments: Vec<&str> = arguments.iter().map(String::as_str).collect();
    // discarded: spawn_flush has already said on stderr why the flush did not start, and the events wait for the next one.
    let _ = telemetry.spawn_flush(Path::new(program), &arguments);
}

/// `telemetry command <name> <exit-status> <duration-ms>`: a command the
/// product ran, queued under usage consent.
fn command(line: &Line, telemetry: &Telemetry, named: &Named) -> ExitCode {
    // discarded: the parser's own words add nothing to the refusal, which names the value and what it must be.
    let Ok(exit_status) = line.operands[1].parse::<i32>() else {
        return number_refused(line, 1, "the exit status");
    };
    // discarded: as above, the refusal names the value and that it must be a whole number.
    let Ok(milliseconds) = line.operands[2].parse::<u64>() else {
        return number_refused(line, 2, "the duration in milliseconds");
    };
    let duration = Duration::from_millis(milliseconds);
    telemetry.command(&line.operands[0], exit_status, duration);
    flush_behind(telemetry, named);
    say::print(&telemetry.status(), line.text)
}

/// The refusal of operand `index` of `line`, which is no whole number of
/// the range it is read into.
fn number_refused(line: &Line, index: usize, what: &str) -> ExitCode {
    say::refuse(
        &own::COMMAND_ARGUMENTS,
        &own::COMMAND_ARGUMENTS_NUMBER_INVALID,
        &[
            ("what", what),
            ("command", &line.command()),
            ("quoted_value", &quoted(&line.operands[index])),
            ("quoted_operands", &quoted(&line.operands)),
            ("usage", line.spec.usage),
        ],
    )
}
