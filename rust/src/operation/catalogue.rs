//! What a functionality's declaration prints and what is wrong with it: its
//! problems, the causes it meets, its JSON listing and its page section, and
//! what only a product's whole catalogue shows.

use super::template::fill;
use super::{Cause, Operation};
use crate::declaration as rules;
use crate::render::escape;
use crate::{Code, Failure};

impl Operation {
    /// Everything wrong with this declaration: a malformed id, an empty entry,
    /// a functionality that uses itself, a duplicate cause, a cause that is
    /// not one, a page without a home. What only the whole catalogue can show
    /// is [`catalogue_problems`].
    pub fn problems(&self) -> Vec<String> {
        let mut problems = Vec::new();
        let id = self.id;
        let named = [("operation", id)];
        if Failure::new(id, Code::Unknown, "operation").is_err() {
            let quoted = escape(id);
            problems.push(fill(
                rules::OPERATION_ID_MALFORMED,
                &[("quoted_id", quoted.as_str()), ("pattern", crate::FAILURE_POINT_PATTERN)],
            ));
        }
        let count = self.entries.len().to_string();
        for (index, entry) in self.entries.iter().enumerate() {
            if entry.trim().is_empty() {
                let position = (index + 1).to_string();
                problems.push(fill(
                    rules::ENTRY_EMPTY,
                    &[("operation", id), ("position", &position), ("count", &count)],
                ));
            }
        }
        if self.uses.iter().any(|used| used.id == id) {
            problems.push(fill(rules::USES_ITSELF, &named));
        }
        if self.summary.trim().is_empty() {
            problems.push(fill(rules::SUMMARY_EMPTY, &named));
        }
        if !self.docs.starts_with("https://") {
            let quoted = escape(self.docs);
            problems.push(fill(rules::DOCS_NOT_HTTPS, &[("operation", id), ("quoted_docs", &quoted)]));
        }
        if self.causes.is_empty() && self.uses.is_empty() {
            problems.push(fill(rules::NO_CAUSE, &named));
        }
        for (index, cause) in self.causes.iter().enumerate() {
            if self.causes[..index].iter().any(|earlier| earlier.id == cause.id) {
                problems.push(fill(
                    rules::DECLARED_TWICE,
                    &[("operation", id), ("kind", "cause"), ("id", cause.id)],
                ));
            }
            problems.extend(
                cause
                    .problems()
                    .into_iter()
                    .map(|problem| format!("operation {id}: {problem}")),
            );
        }
        problems.extend(crate::warning::declaration_problems(self));
        problems
    }

    /// Every cause this functionality can meet: its own, then those of each
    /// functionality it uses, each listed once, with the functionality that
    /// declares it.
    pub fn met(&self) -> Vec<(&'static str, &'static Cause)> {
        let mut met: Vec<(&'static str, &'static Cause)> = Vec::new();
        let mut seen: Vec<&'static str> = Vec::new();
        collect(self.id, self.causes, self.uses, &mut met, &mut seen);
        met
    }

    /// The catalogue as one JSON document.
    pub fn to_json(&self, failure_exit: i32) -> String {
        let causes: Vec<String> = self
            .causes
            .iter()
            .map(|cause| cause.to_json(self, failure_exit))
            .collect();
        let entries: Vec<String> = self.entries.iter().map(|entry| escape(entry)).collect();
        let uses: Vec<String> = self.uses.iter().map(|used| escape(used.id)).collect();
        format!(
            "{{\"operation\":{},\"entries\":[{}],\"uses\":[{}],\"summary\":{},\"docs\":{},\"causes\":[{}]}}",
            escape(self.id),
            entries.join(","),
            uses.join(","),
            escape(self.summary),
            escape(self.docs),
            causes.join(",")
        )
    }

    /// The functionality's section of its documentation page: how it is
    /// started, what it uses, and one entry per cause of its own, each with
    /// its anchor, so every refusal is listed verbatim.
    pub fn markdown(&self, failure_exit: i32) -> String {
        let listed = |items: Vec<String>, none: &str| {
            if items.is_empty() {
                none.to_owned()
            } else {
                items.join(", ")
            }
        };
        let entries = listed(
            self.entries.iter().map(|entry| format!("`{entry}`")).collect(),
            "run only by the functionalities that use it",
        );
        let uses = listed(self.uses.iter().map(|used| format!("`{}`", used.id)).collect(), "none");
        let mut page = format!(
            "## `{}`\n\n{}\n\nStarted through: {entries}. Uses: {uses}. Failure catalogue `{}`: {} declared cause(s) of its own.\n",
            self.id,
            self.summary,
            self.id,
            self.causes.len()
        );
        for cause in self.causes {
            let retry = if cause.code.retryable() {
                "retrying unchanged can help"
            } else {
                "retrying unchanged will not help"
            };
            page.push_str(&format!(
                "\n<a id=\"{anchor}\"></a>\n\n### `{operation}.{id}`\n\n\
                 - **What failed:** {failed}\n\
                 - **Cause:** {cause_text}\n\
                 - **Observed state shown:** {observed}\n\
                 - **Fix:** {remedy}\n\
                 - **Code:** `{code}`, exit {exit}; {retry}\n\
                 - **Test:** `{test}`\n",
                anchor = cause.anchor(self),
                operation = self.id,
                id = cause.id,
                failed = cause.failed,
                cause_text = cause.cause,
                observed = cause.observed,
                remedy = cause.remedy,
                code = cause.code,
                exit = cause.exit_code(failure_exit),
                test = cause.test,
            ));
        }
        page
    }
}

/// The causes of `owner` and of every functionality it uses, transitively,
/// each functionality visited once.
fn collect(
    owner: &'static str,
    causes: &'static [&'static Cause],
    uses: &'static [&'static Operation],
    met: &mut Vec<(&'static str, &'static Cause)>,
    seen: &mut Vec<&'static str>,
) {
    if seen.contains(&owner) {
        return;
    }
    seen.push(owner);
    for cause in causes {
        met.push((owner, *cause));
    }
    for used in uses {
        collect(used.id, used.causes, used.uses, met, seen);
    }
}

/// What only a product's whole catalogue shows, each as one sentence: a
/// functionality declared twice, one that uses a functionality the catalogue
/// does not list, and one nothing starts — no entry names it and no listed
/// functionality uses it, so no reader can reach its causes.
pub fn catalogue_problems(operations: &[&Operation]) -> Vec<String> {
    let mut problems = Vec::new();
    for (index, operation) in operations.iter().enumerate() {
        let named = [("operation", operation.id)];
        if operations[..index].iter().any(|earlier| earlier.id == operation.id) {
            problems.push(fill(rules::OPERATION_TWICE, &named));
        }
        for used in operation.uses {
            if !operations.iter().any(|listed| listed.id == used.id) {
                problems.push(fill(rules::USES_UNLISTED, &[("operation", operation.id), ("used", used.id)]));
            }
        }
        let used = operations
            .iter()
            .any(|other| other.uses.iter().any(|used| used.id == operation.id));
        if operation.entries.is_empty() && !used {
            problems.push(fill(rules::NOTHING_STARTS, &named));
        }
    }
    problems
}
