//! One way a functionality can fail, and the rules its declaration is held
//! to; the rules and their sentences come from catalogue/declaration.json.

use super::template::{fill, template_problems, unfilled};
use super::Operation;
use crate::declaration as rules;
use crate::render::escape;
use crate::{Code, Failure, GENERIC_SENTENCES};

/// One way an operation can fail.
///
/// The four sentences are templates: `{name}` is replaced by the value the
/// raising code supplies, so the refusal names the actual target, fleet or
/// path while the catalogue states the shape once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cause {
    /// Stable within its operation: lowercase words joined by `-`.
    pub id: &'static str,
    pub code: Code,
    /// The request was refused for its own form and exits with
    /// [`Code::USAGE_EXIT`]; such a cause is never retryable.
    pub usage: bool,
    /// The product's own documented exit status for this cause, where it has
    /// one (a lost compare-and-swap, say). A usage refusal and a retryable
    /// code take theirs from the catalogue and declare none.
    pub exit: Option<i32>,
    /// The step that failed, as the reader would name it.
    pub failed: &'static str,
    /// Why it failed, in words of its own; the raw text of the layer below
    /// goes in `observed`.
    pub cause: &'static str,
    /// The state the refusal shows: the values that do exist, the path read,
    /// what the layer below answered.
    pub observed: &'static str,
    /// What would fix it: the command to run, the declaration to change.
    pub remedy: &'static str,
    /// The real test that provokes this cause:
    /// `tests/<area>/<file>::<test name>`.
    pub test: &'static str,
}

pub(crate) fn is_cause_id(id: &str) -> bool {
    !id.is_empty()
        && id.split('-').all(|word| {
            !word.is_empty()
                && word
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        })
        && id.as_bytes()[0].is_ascii_lowercase()
}

/// `tests/<area>/<file>::<test name>`, the shape every product's tests take
/// ([`rules::TEST_PATH_PATTERN`]).
pub(crate) fn is_test_path(test: &str) -> bool {
    let Some((path, name)) = test.split_once("::") else {
        return false;
    };
    let segments: Vec<&str> = path.split('/').collect();
    segments.len() >= 3
        && segments[0] == "tests"
        && segments
            .iter()
            .all(|segment| !segment.is_empty() && !segment.contains(':'))
        && !name.is_empty()
        && name
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
}

/// The problems of the texts every declaration kind shares: each field empty,
/// generic, or holding a placeholder the renderer never fills; `kind` is
/// `cause` or `warning`.
pub(crate) fn text_problems(kind: &str, id: &str, fields: &[(&str, &str)]) -> Vec<String> {
    let mut problems = Vec::new();
    for &(field, text) in fields {
        if text.trim().is_empty() {
            problems.push(fill(
                rules::FIELD_EMPTY,
                &[("kind", kind), ("id", id), ("field", field), ("meaning", rules::field_meaning(field))],
            ));
            continue;
        }
        let lower = text.to_lowercase();
        for sentence in GENERIC_SENTENCES {
            if lower.contains(sentence.text) {
                let quoted = escape(sentence.text);
                problems.push(fill(
                    rules::FIELD_GENERIC,
                    &[("kind", kind), ("id", id), ("field", field), ("quoted_text", &quoted), ("reason", sentence.reason)],
                ));
            }
        }
        problems.extend(template_problems(kind, id, field, text));
    }
    problems
}

impl Cause {
    /// The exit status this cause leaves a command with, given the product's
    /// own failure status: the usage status for a usage refusal, the retry
    /// status for a retryable code, the product's own otherwise.
    pub fn exit_code(&self, failure_exit: i32) -> i32 {
        if self.usage {
            Code::USAGE_EXIT
        } else if let Some(exit) = self.exit {
            exit
        } else {
            self.code.exit_code(failure_exit)
        }
    }

    /// What failed, why, and the state observed, as one sentence.
    pub fn sentence(&self, values: &[(&str, &str)]) -> String {
        format!(
            "{}: {}; observed: {}",
            fill(self.failed, values),
            fill(self.cause, values),
            fill(self.observed, values)
        )
    }

    /// What would fix it, with the values filled in.
    pub fn fix(&self, values: &[(&str, &str)]) -> String {
        fill(self.remedy, values)
    }

    /// The sentence and the fix as one line: what an error of this crate's
    /// own says when it is displayed.
    pub fn refusal(&self, values: &[(&str, &str)]) -> String {
        format!("{}; fix: {}", self.sentence(values), self.fix(values))
    }

    /// The placeholders of this cause that `values` gives no value for.
    pub fn unfilled(&self, values: &[(&str, &str)]) -> Vec<&'static str> {
        unfilled(&[self.failed, self.cause, self.observed, self.remedy], values)
    }

    /// The envelope this cause raises at `failure_point`. A placeholder the
    /// raising code gave no value for is recorded under
    /// `wisent_errors.unfilled`, so the gap travels in the data.
    pub fn failure(&self, failure_point: &str, service: &str, values: &[(&str, &str)]) -> Failure {
        let failure = Failure::or_fallback(failure_point, self.code, service)
            .detail(self.sentence(values))
            .remedy(self.fix(values))
            .with_context("cause", self.id);
        let missing = self.unfilled(values);
        if missing.is_empty() {
            failure
        } else {
            failure.with_context("wisent_errors.unfilled", missing.join(","))
        }
    }

    /// Everything wrong with this declaration, each as one sentence.
    pub fn problems(&self) -> Vec<String> {
        let id = self.id;
        let mut problems = Vec::new();
        if !is_cause_id(id) {
            let quoted = escape(id);
            problems.push(fill(
                rules::ID_MALFORMED,
                &[("kind", "cause"), ("quoted_id", &quoted), ("pattern", rules::CAUSE_ID_PATTERN)],
            ));
        }
        problems.extend(text_problems(
            "cause",
            id,
            &[("failed", self.failed), ("cause", self.cause), ("observed", self.observed), ("remedy", self.remedy)],
        ));
        let codes: Vec<&str> = Code::ALL
            .iter()
            .filter(|code| **code != Code::Unknown)
            .map(|code| code.as_str())
            .collect();
        if self.code == Code::Unknown {
            problems.push(fill(rules::CODE_UNKNOWN, &[("id", id), ("codes", &codes.join(", "))]));
        } else if self.usage && self.code.retryable() {
            problems.push(fill(rules::USAGE_RETRYABLE, &[("id", id), ("code", self.code.as_str())]));
        }
        if let Some(status) = self.exit {
            let (exit, usage, retry) = (status.to_string(), Code::USAGE_EXIT.to_string(), Code::RETRY_EXIT.to_string());
            let limits = [("id", id), ("exit", exit.as_str()), ("usage_exit", usage.as_str()), ("retry_exit", retry.as_str())];
            if self.usage || self.code.retryable() {
                problems.push(fill(rules::EXIT_BESIDE_DERIVED, &limits));
            }
            if [0, Code::USAGE_EXIT, Code::RETRY_EXIT].contains(&status) {
                problems.push(fill(rules::EXIT_NOT_OWN, &limits));
            }
        }
        if !is_test_path(self.test) {
            let quoted = escape(self.test);
            problems.push(fill(
                rules::TEST_MALFORMED,
                &[("kind", "cause"), ("id", id), ("quoted_test", &quoted), ("pattern", rules::TEST_PATH_PATTERN)],
            ));
        }
        problems
    }

    /// The anchor of this cause's line on its operation's page.
    pub fn anchor(&self, operation: &Operation) -> String {
        format!("{}-{}", operation.id.replace('.', "-"), self.id)
    }

    pub(super) fn to_json(self, operation: &Operation, failure_exit: i32) -> String {
        format!(
            "{{\"id\":{},\"code\":{},\"exit\":{},\"retryable\":{},\"usage\":{},\"failed\":{},\"cause\":{},\"observed\":{},\"remedy\":{},\"test\":{},\"doc\":{}}}",
            escape(self.id),
            escape(self.code.as_str()),
            self.exit_code(failure_exit),
            self.code.retryable(),
            self.usage,
            escape(self.failed),
            escape(self.cause),
            escape(self.observed),
            escape(self.remedy),
            escape(self.test),
            escape(&format!("{}#{}", operation.docs, self.anchor(operation))),
        )
    }
}
