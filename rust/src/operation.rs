//! A functionality's failure catalogue: every way one functionality of a
//! product can fail, declared in code beside the code that raises it.
//!
//! "Operation did not succeed" is a failure nobody analysed. A declared cause
//! is the analysis written down once: which step failed, why, which state the
//! reader is shown, what fixes it, the code and the exit status it leaves, the
//! test that provokes it and the documentation line that lists it. The
//! catalogue holds every cause the functionality can meet, including the ones
//! nobody has met yet, because the reader who meets one first has nothing
//! else to go on.
//!
//! The unit is the functionality, not the command that starts it. One command
//! runs several functionalities (a registry read, a store write, a connection
//! to a host), and many run with no command at all: a worker's loop, an API
//! route, a desktop screen, a routine. So an [`Operation`] is one
//! functionality, named by its failure point; it lists the `entries` a user or
//! a program starts it through and the functionalities it `uses`, whose causes
//! it meets without declaring them again.
//!
//! The same declaration produces the refusal the operator reads, the envelope
//! a machine reads, the `errors show` listing and the documentation page, so
//! none of them can say something the others do not.

use crate::render::escape;
use crate::{Code, Failure, GenericSentence, GENERIC_SENTENCES};

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
    /// Why it failed.
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

/// One functionality and every cause it can fail with.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Operation {
    /// The functionality's failure point: a dotted lowercase path,
    /// `stado.registry.read`.
    pub id: &'static str,
    /// Every way a user or a program starts it, as they meet it: a command
    /// (`stado fleet enroll`), a route (`POST /v1/jobs`), a screen
    /// (`Desktop: Hosts → Enroll`), a routine or a library call. A
    /// functionality only other functionalities run has none and is listed
    /// in their `uses`.
    pub entries: &'static [&'static str],
    /// The functionalities it runs, whose causes it meets as they declare
    /// them.
    pub uses: &'static [&'static Operation],
    pub summary: &'static str,
    /// The functionality's documentation page; each cause is a line on it.
    pub docs: &'static str,
    /// The causes of its own steps; a functionality made only of the ones it
    /// uses declares none.
    pub causes: &'static [&'static Cause],
}

/// `template` with each `{name}` replaced by its value.
///
/// A placeholder with no value stays as written, so a value the raising code
/// forgot is visible in the sentence instead of silently becoming nothing.
pub fn fill(template: &str, values: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(template.len());
    let mut rest = template;
    while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        match after.find('}') {
            Some(close) => {
                let name = &after[..close];
                match values.iter().find(|(key, _)| *key == name) {
                    Some((_, value)) => out.push_str(value),
                    None => {
                        out.push('{');
                        out.push_str(name);
                        out.push('}');
                    }
                }
                rest = &after[close + 1..];
            }
            None => {
                out.push_str(&rest[open..]);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

/// The placeholders a template names, in order of appearance.
pub fn placeholders(template: &str) -> Vec<&str> {
    let mut names = Vec::new();
    let mut rest = template;
    while let Some(open) = rest.find('{') {
        let after = &rest[open + 1..];
        let Some(close) = after.find('}') else { break };
        names.push(&after[..close]);
        rest = &after[close + 1..];
    }
    names
}

/// The generic sentences inside the string literals of one source line.
///
/// Comment lines are skipped: a comment that explains why a sentence is
/// generic is not an error message. `single_quoted` also reads `'...'` as a
/// literal, which is right for JavaScript and Python and wrong for Rust, where
/// a quote opens a lifetime or a character.
pub fn generic_sentences_in(line: &str, single_quoted: bool) -> Vec<&'static GenericSentence> {
    let trimmed = line.trim_start();
    if ["//", "/*", "*", "#", "--"]
        .iter()
        .any(|marker| trimmed.starts_with(marker))
    {
        return Vec::new();
    }
    let mut found = Vec::new();
    for literal in literals(line, single_quoted) {
        let lower = literal.to_lowercase();
        for sentence in GENERIC_SENTENCES {
            if lower.contains(sentence.text) && !found.contains(&sentence) {
                found.push(sentence);
            }
        }
    }
    found
}

/// The quoted segments of one line, escapes kept.
fn literals(line: &str, single_quoted: bool) -> Vec<&str> {
    let mut segments = Vec::new();
    let bytes = line.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        let quote = bytes[index];
        let opens = quote == b'"' || quote == b'`' || (single_quoted && quote == b'\'');
        if !opens {
            index += 1;
            continue;
        }
        let start = index + 1;
        let mut end = start;
        while end < bytes.len() && bytes[end] != quote {
            end += if bytes[end] == b'\\' { 2 } else { 1 };
        }
        let end = end.min(bytes.len());
        segments.push(&line[start..end]);
        index = end + 1;
    }
    segments
}

fn is_cause_id(id: &str) -> bool {
    !id.is_empty()
        && id.split('-').all(|word| {
            !word.is_empty()
                && word
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        })
        && id.as_bytes()[0].is_ascii_lowercase()
}

/// `tests/<area>/<file>::<test name>`, the shape every product's tests take.
fn is_test_path(test: &str) -> bool {
    let Some((path, name)) = test.split_once("::") else {
        return false;
    };
    let segments: Vec<&str> = path.split('/').collect();
    segments.len() >= 3
        && segments[0] == "tests"
        && segments.iter().all(|segment| !segment.is_empty())
        && !name.is_empty()
        && name
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
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

    /// The envelope this cause raises at `failure_point`.
    pub fn failure(&self, failure_point: &str, service: &str, values: &[(&str, &str)]) -> Failure {
        Failure::or_fallback(failure_point, self.code, service)
            .detail(self.sentence(values))
            .remedy(self.fix(values))
            .with_context("cause", self.id)
    }

    /// Everything wrong with this declaration, each as one sentence.
    pub fn problems(&self) -> Vec<String> {
        let mut problems = Vec::new();
        let id = self.id;
        if !is_cause_id(id) {
            problems.push(format!(
                "cause {id:?}: the id is not lowercase words joined by '-'"
            ));
        }
        for (field, text) in [
            ("failed", self.failed),
            ("cause", self.cause),
            ("observed", self.observed),
            ("remedy", self.remedy),
        ] {
            if text.trim().is_empty() {
                problems.push(format!("cause {id}: `{field}` is empty"));
                continue;
            }
            let lower = text.to_lowercase();
            for sentence in GENERIC_SENTENCES {
                if lower.contains(sentence.text) {
                    problems.push(format!(
                        "cause {id}: `{field}` says {:?}, which {}",
                        sentence.text, sentence.reason
                    ));
                }
            }
        }
        if self.code == Code::Unknown {
            problems.push(format!(
                "cause {id}: a declared cause is never `unknown`; `unknown` is the catch-all a declaration replaces"
            ));
        }
        if self.usage && self.code.retryable() {
            problems.push(format!(
                "cause {id}: a usage refusal cannot be `{}`, which is retryable",
                self.code
            ));
        }
        if let Some(exit) = self.exit {
            if self.usage || self.code.retryable() {
                problems.push(format!(
                    "cause {id}: exit {exit} is declared, but a usage refusal exits {} and a retryable code {}",
                    Code::USAGE_EXIT,
                    Code::RETRY_EXIT
                ));
            }
            if exit == 0 || exit == Code::USAGE_EXIT || exit == Code::RETRY_EXIT {
                problems.push(format!(
                    "cause {id}: exit {exit} is not a status of its own: 0 is success, {} usage and {} retry",
                    Code::USAGE_EXIT,
                    Code::RETRY_EXIT
                ));
            }
        }
        if !is_test_path(self.test) {
            problems.push(format!(
                "cause {id}: test {:?} is not tests/<area>/<file>::<test name>",
                self.test
            ));
        }
        problems
    }

    /// The anchor of this cause's line on its operation's page.
    pub fn anchor(&self, operation: &Operation) -> String {
        format!("{}-{}", operation.id.replace('.', "-"), self.id)
    }

    fn to_json(self, operation: &Operation, failure_exit: i32) -> String {
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

impl Operation {
    /// The declared cause with this id.
    pub fn cause(&self, id: &str) -> Option<&'static Cause> {
        self.causes.iter().copied().find(|cause| cause.id == id)
    }

    /// Everything wrong with this declaration: a malformed id, an empty entry,
    /// a functionality that uses itself, a duplicate cause, a cause without
    /// its test or a page without a home. What only the whole catalogue can
    /// show is [`catalogue_problems`].
    pub fn problems(&self) -> Vec<String> {
        let mut problems = Vec::new();
        let id = self.id;
        if Failure::new(id, Code::Unknown, "operation").is_err() {
            problems.push(format!(
                "operation {id:?}: the id is not a dotted lowercase path"
            ));
        }
        if self.entries.iter().any(|entry| entry.trim().is_empty()) {
            problems.push(format!("operation {id}: an entry is empty"));
        }
        if self.uses.iter().any(|used| used.id == id) {
            problems.push(format!("operation {id}: it lists itself in `uses`"));
        }
        if self.summary.trim().is_empty() {
            problems.push(format!("operation {id}: `summary` is empty"));
        }
        if !self.docs.starts_with("https://") {
            problems.push(format!(
                "operation {id}: docs {:?} is not an https page",
                self.docs
            ));
        }
        if self.causes.is_empty() && self.uses.is_empty() {
            problems.push(format!(
                "operation {id}: declares no cause and uses no functionality that declares one"
            ));
        }
        for (index, cause) in self.causes.iter().enumerate() {
            if self.causes[..index]
                .iter()
                .any(|earlier| earlier.id == cause.id)
            {
                problems.push(format!(
                    "operation {id}: cause {} is declared twice",
                    cause.id
                ));
            }
            problems.extend(
                cause
                    .problems()
                    .into_iter()
                    .map(|problem| format!("operation {id}: {problem}")),
            );
        }
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
        let entries = if self.entries.is_empty() {
            "run only by the functionalities that use it".to_owned()
        } else {
            self.entries
                .iter()
                .map(|entry| format!("`{entry}`"))
                .collect::<Vec<_>>()
                .join(", ")
        };
        let uses = if self.uses.is_empty() {
            "none".to_owned()
        } else {
            self.uses
                .iter()
                .map(|used| format!("`{}`", used.id))
                .collect::<Vec<_>>()
                .join(", ")
        };
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
        if operations[..index]
            .iter()
            .any(|earlier| earlier.id == operation.id)
        {
            problems.push(format!("operation {} is declared twice", operation.id));
        }
        for used in operation.uses {
            if !operations.iter().any(|listed| listed.id == used.id) {
                problems.push(format!(
                    "operation {}: it uses {}, which the catalogue does not list; list every functionality the product runs",
                    operation.id, used.id
                ));
            }
        }
        let used = operations
            .iter()
            .any(|other| other.uses.iter().any(|used| used.id == operation.id));
        if operation.entries.is_empty() && !used {
            problems.push(format!(
                "operation {}: nothing starts it: it names no entry and no functionality of the catalogue uses it",
                operation.id
            ));
        }
    }
    problems
}
