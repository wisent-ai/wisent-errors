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
    Fails(Failure),
    Skipped(&'static str),
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
                    Err(failure) => State::Fails(failure),
                },
                Probe::Skipped(why) => State::Skipped(why),
            },
        })
        .collect()
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
        match checks
            .iter()
            .filter(|check| check.operation.id == operation.id)
            .count()
        {
            0 => problems.push(format!(
                "{} has an entry point and no diagnosis check: give it a Probe::Run, or a \
                 Probe::Skipped saying why it is not tried",
                operation.id
            )),
            1 => {}
            count => problems.push(format!("{} is checked {count} times", operation.id)),
        }
    }
    for check in checks {
        if !operations
            .iter()
            .any(|operation| operation.id == check.operation.id)
        {
            problems.push(format!(
                "{} is checked but the catalogue does not declare it",
                check.operation.id
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
                State::Fails(failure) => format!(
                    "failed  {id}: {}; fix: {}",
                    failure
                        .detail
                        .as_deref()
                        .unwrap_or("it failed and said nothing more"),
                    failure.remedy.as_deref().unwrap_or("no remedy is declared")
                ),
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
                    State::Fails(failure) => json!({
                        "operation": id,
                        "state": "fails",
                        "failure_point": failure.failure_point,
                        "error_code": failure.code.as_str(),
                        "detail": failure.detail,
                        "remedy": failure.remedy,
                    }),
                    State::Skipped(why) => json!({"operation": id, "state": "skipped", "why": why}),
                }
            })
            .collect(),
    )
}
