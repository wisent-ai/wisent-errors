//! `<product> doctor`: every functionality a product's catalogue declares,
//! tried now on this machine, each answered as working, failing with what
//! failed and how to fix it, or not tried and why.
//!
//! The list is the catalogue's own (`docs/diagnosis.md`). A product gives
//! one [`Check`] per functionality that has an entry point, and
//! [`problems`] names a functionality with no check, one checked twice and a
//! check of a functionality the catalogue does not declare, so a new
//! functionality is in the diagnosis the moment it is declared, or the
//! product's catalogue test fails.

use serde_json::{json, Value};

use crate::failures as own;
use crate::{Failure, Operation};

/// How one functionality is tried.
pub enum Probe {
    /// Tried now. `Ok` says what was observed working; `Err` is the failure
    /// a user would meet, with its detail and remedy.
    Run(fn() -> Result<String, Failure>),
    /// Not tried, and why: it changes the user's data, or it needs input
    /// only its own command carries.
    Skipped(&'static str),
}

/// One functionality of the catalogue and how the diagnosis tries it.
pub struct Check {
    pub operation: &'static Operation,
    pub probe: Probe,
}

/// What the diagnosis found for one functionality.
pub enum State {
    Works(String),
    Fails(Failed),
    Skipped(&'static str),
}

/// A functionality that failed, with what failed and what fixes it: the
/// probe's own failure when it says both, the diagnosis's refusal of it
/// (`wisent_errors.cli_output.diagnose.probe-failure-unexplained`) when it
/// does not. Only [`diagnose`] makes one, so every failure printed says both.
pub struct Failed {
    failure: Failure,
    detail: String,
    remedy: String,
}

impl Failed {
    /// The envelope, as the probe or the diagnosis raised it.
    pub fn failure(&self) -> &Failure {
        &self.failure
    }

    /// What failed, why, and the state observed.
    pub fn detail(&self) -> &str {
        &self.detail
    }

    /// What fixes it.
    pub fn remedy(&self) -> &str {
        &self.remedy
    }
}

pub struct Finding {
    pub operation: &'static Operation,
    pub state: State,
}

/// Try every check, in the catalogue's order.
pub fn diagnose(checks: &[Check]) -> Vec<Finding> {
    checks
        .iter()
        .map(|check| Finding {
            operation: check.operation,
            state: match &check.probe {
                Probe::Run(probe) => match probe() {
                    Ok(observed) => State::Works(observed),
                    Err(failure) => State::Fails(failed(check.operation, failure)),
                },
                Probe::Skipped(why) => State::Skipped(why),
            },
        })
        .collect()
}

/// The probe's failure when it says what failed and what fixes it, or the
/// diagnosis's declared refusal of one that does not.
fn failed(operation: &Operation, failure: Failure) -> Failed {
    let missing = match (&failure.detail, &failure.remedy) {
        (Some(detail), Some(remedy)) => {
            let (detail, remedy) = (detail.clone(), remedy.clone());
            return Failed { failure, detail, remedy };
        }
        (None, Some(_)) => "no detail",
        (Some(_), None) => "no remedy",
        (None, None) => "neither a detail nor a remedy",
    };
    let cause = &own::CLI_OUTPUT_DIAGNOSE_PROBE_FAILURE_UNEXPLAINED;
    let values = [
        ("operation", operation.id),
        ("missing", missing),
        ("failure_point", failure.failure_point.as_str()),
        ("code", failure.code.as_str()),
    ];
    Failed {
        detail: cause.sentence(&values),
        remedy: cause.fix(&values),
        failure: cause.failure(own::CLI_OUTPUT_DIAGNOSE.id, &failure.service, &values),
    }
}

/// Every way `checks` and the catalogue `operations` disagree: a
/// functionality with an entry point and no check, one checked twice, and a
/// check of a functionality the catalogue does not declare.
pub fn problems(operations: &[&'static Operation], checks: &[Check]) -> Vec<String> {
    let mut problems = Vec::new();
    for operation in operations
        .iter()
        .filter(|operation| !operation.entries.is_empty())
    {
        let checked: Vec<_> = checks
            .iter()
            .filter(|check| check.operation.id == operation.id)
            .collect();
        match checked.as_slice() {
            [] => problems.push(format!(
                "{} has an entry point and no diagnosis check: give it a Probe::Run, or a \
                 Probe::Skipped saying why it is not tried",
                operation.id
            )),
            [_] => {}
            many => problems.push(format!(
                "{} is checked {} times, so the diagnosis would try it more than once and print each answer: keep one Check for it, a Probe::Run or a Probe::Skipped, and drop the others",
                operation.id,
                many.len()
            )),
        }
    }
    for check in checks {
        if !operations
            .iter()
            .any(|operation| operation.id == check.operation.id)
        {
            let declared: Vec<&str> = operations.iter().map(|operation| operation.id).collect();
            problems.push(format!(
                "{} is checked but the catalogue does not declare it; the catalogue declares {}: declare it in the catalogue, or drop its Check",
                check.operation.id,
                declared.join(", ")
            ));
        }
    }
    problems
}

/// 0 when nothing failed, 1 when a functionality failed.
pub fn exit_status(findings: &[Finding]) -> i32 {
    match findings
        .iter()
        .any(|finding| matches!(finding.state, State::Fails(_)))
    {
        true => 1,
        false => 0,
    }
}

/// One line per functionality, the way `<product> doctor` prints them.
pub fn render(findings: &[Finding]) -> String {
    findings
        .iter()
        .map(|finding| {
            let id = finding.operation.id;
            match &finding.state {
                State::Works(observed) => format!("ok      {id}: {observed}"),
                State::Fails(failed) => format!("failed  {id}: {}; fix: {}", failed.detail(), failed.remedy()),
                State::Skipped(why) => format!("skipped {id}: {why}"),
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// The findings as `<product> doctor --json` prints them.
pub fn to_json(findings: &[Finding]) -> Value {
    Value::Array(
        findings
            .iter()
            .map(|finding| {
                let id = finding.operation.id;
                match &finding.state {
                    State::Works(observed) => {
                        json!({"operation": id, "state": "works", "observed": observed})
                    }
                    State::Fails(failed) => json!({
                        "operation": id,
                        "state": "fails",
                        "failure_point": failed.failure().failure_point,
                        "error_code": failed.failure().code.as_str(),
                        "detail": failed.detail(),
                        "remedy": failed.remedy(),
                    }),
                    State::Skipped(why) => json!({"operation": id, "state": "skipped", "why": why}),
                }
            })
            .collect(),
    )
}
