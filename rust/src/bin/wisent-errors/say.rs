//! What the command prints: a result through `cli_output::output`, a text
//! as it is, and a refusal as the three lines every command of this package
//! prints (ci/support/refuse.mjs):
//!
//!   Error: <failed>: <cause>; observed: <observed>
//!   fix: <remedy>
//!   cause: <operation>.<cause id>; <page>#<anchor>
//!
//! exiting with the status the cause declares (`Cause::exit_code`).

use std::io::Write;
use std::process::ExitCode;

use serde_json::Value;
use wisent_errors::failures as own;
use wisent_errors::{cli_output, telemetry, Cause, Code, Failure, Operation, Warning};

/// The status a command fails with when its cause declares none, C's
/// EXIT_FAILURE: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
pub const EXIT_FAILURE: i32 = 1;

/// The page every warning of the command links to.
pub const WARNINGS_PAGE: &str = "https://github.com/wisent-ai/wisent-errors/blob/main/docs/command-line.md";

/// Every functionality the command runs, whose causes a refusal names, in
/// the order `errors list` prints them.
pub fn catalogue() -> impl Iterator<Item = &'static Operation> {
    [
        &own::COMMAND_ARGUMENTS,
        &own::COMMAND_PRODUCT,
        &own::COMMAND_CHECK,
        &own::CLI_OUTPUT_READ_JSON,
        &own::CLI_OUTPUT_PRINT,
        &own::CLI_OUTPUT_DIAGNOSE,
        &own::ENVELOPE_BUILD,
    ]
    .into_iter()
    .chain(telemetry::operations())
}

/// Leave with `status`.
pub fn exit(status: i32) -> ExitCode {
    // fallback: every status a cause declares is 1 to 255; one outside it leaves as a failure.
    u8::try_from(status).map_or(ExitCode::FAILURE, ExitCode::from)
}

/// Write `text` and a line end to standard error. Standard error is where
/// a refusal is said; when it cannot be written there is nowhere left to
/// say that, and the exit status still carries the refusal.
fn stderr(text: &str) {
    // discarded: a standard error that cannot be written leaves the exit status as the only report.
    let _ = writeln!(std::io::stderr().lock(), "{text}");
}

/// Say the declared refusal of `cause` of `operation` with `values`.
pub fn refuse(operation: &Operation, cause: &Cause, values: &[(&str, &str)]) -> ExitCode {
    let mut text = format!(
        "Error: {}\nfix: {}\ncause: {}.{}; {}#{}",
        cause.sentence(values),
        cause.fix(values),
        operation.id,
        cause.id,
        operation.docs,
        cause.anchor(operation)
    );
    let missing = cause.unfilled(values);
    if !missing.is_empty() {
        text.push_str(&format!("\nwisent_errors.unfilled: {}", missing.join(", ")));
    }
    stderr(&text);
    exit(cause.exit_code(EXIT_FAILURE))
}

/// [`refuse`], with the values a refusal of the library answers.
pub fn refuse_owned(operation: &Operation, cause: &Cause, values: &[(&'static str, String)]) -> ExitCode {
    let borrowed: Vec<(&str, &str)> = values.iter().map(|(key, value)| (*key, value.as_str())).collect();
    refuse(operation, cause, &borrowed)
}

/// Say a failure the library raised from one of its declared causes, as
/// [`refuse`] says it: its detail, its remedy, and the cause its context
/// names.
pub fn refuse_failure(failure: &Failure) -> ExitCode {
    let declared = failure.context.get("cause").and_then(|id| {
        catalogue().find_map(|operation| operation.cause(id).map(|cause| (operation, cause)))
    });
    // fallback: every failure the library raises is a declared cause's, which carries a detail; the code's summary stands in otherwise.
    let detail = failure.detail.as_deref().unwrap_or(failure.code.operator_summary());
    let mut text = format!("Error: {detail}");
    if let Some(remedy) = &failure.remedy {
        text.push_str(&format!("\nfix: {remedy}"));
    }
    let status = match declared {
        Some((operation, cause)) => {
            text.push_str(&format!("\ncause: {}.{}; {}#{}", operation.id, cause.id, operation.docs, cause.anchor(operation)));
            cause.exit_code(EXIT_FAILURE)
        }
        None => {
            text.push_str(&format!(
                "\ncause: {} ({}); no cause this command declares names it",
                failure.failure_point, failure.code
            ));
            failure.code.exit_code(EXIT_FAILURE)
        }
    };
    if let Some(missing) = failure.context.get("wisent_errors.unfilled") {
        text.push_str(&format!("\nwisent_errors.unfilled: {missing}"));
    }
    stderr(&text);
    exit(status)
}

/// Say what `warning` of `operation` warns of, that nothing was done, and how
/// to go ahead, and leave with the usage status: the command line lacked
/// its confirmation.
pub fn unconfirmed(operation: &Operation, warning: &Warning, values: &[(&str, &str)]) -> ExitCode {
    stderr(&format!(
        "Warning: {}\nwarning: {}.{}; {WARNINGS_PAGE}#{}",
        warning.unconfirmed(values),
        operation.id,
        warning.id,
        warning.anchor(operation)
    ));
    exit(Code::USAGE_EXIT)
}

/// Print `value` as pretty JSON, or with `text` one `path: value` line per
/// field, through `cli_output::output`; a standard output it cannot write
/// is its declared refusal.
pub fn print(value: &Value, text: bool) -> ExitCode {
    let Err(refused) = cli_output::output::<_, serde_json::Error>(value, text) else {
        return ExitCode::SUCCESS;
    };
    let refused = std::io::Error::from(refused);
    let cause = match refused.kind() {
        std::io::ErrorKind::BrokenPipe => &own::CLI_OUTPUT_PRINT_OUTPUT_CLOSED,
        std::io::ErrorKind::InvalidData => &own::CLI_OUTPUT_PRINT_DOCUMENT_UNREPRESENTABLE,
        _ => &own::CLI_OUTPUT_PRINT_OUTPUT_UNWRITABLE,
    };
    // `output` answers the cause's refusal as one line, `<sentence>; fix:
    // <fix>` (`Cause::refusal`); it is said here as the three lines.
    let said = refused.to_string();
    // fallback: a message without the fix's separator is said whole, with the cause's declared remedy as its fix.
    let (sentence, fix) = said.split_once("; fix: ").unwrap_or((said.as_str(), cause.remedy));
    let operation = &own::CLI_OUTPUT_PRINT;
    stderr(&format!(
        "Error: {sentence}\nfix: {fix}\ncause: {}.{}; {}#{}",
        operation.id,
        cause.id,
        operation.docs,
        cause.anchor(operation)
    ));
    exit(cause.exit_code(EXIT_FAILURE))
}

/// Print `body` and a line end as it is: a page, the doctor's lines.
pub fn print_text(body: &str) -> ExitCode {
    let mut stdout = std::io::stdout().lock();
    let Err(error) = writeln!(stdout, "{body}").and_then(|()| stdout.flush()) else {
        return ExitCode::SUCCESS;
    };
    let (bytes, kind, shown) = ((body.len() + 1).to_string(), format!("{:?}", error.kind()), error.to_string());
    let cause = match error.kind() {
        std::io::ErrorKind::BrokenPipe => &own::CLI_OUTPUT_PRINT_OUTPUT_CLOSED,
        _ => &own::CLI_OUTPUT_PRINT_OUTPUT_UNWRITABLE,
    };
    refuse(&own::CLI_OUTPUT_PRINT, cause, &[("bytes", &bytes), ("kind", &kind), ("error", &shown)])
}
