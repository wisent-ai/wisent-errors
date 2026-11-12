//! A functionality's warnings: what one functionality of a product does that
//! its caller must know before it runs, declared in code beside the
//! functionality's causes ([`crate::Operation::warnings`]).
//!
//! A failure catalogue says how a functionality can go wrong. A warning says
//! what it does when it goes right and the caller still loses something: an
//! item purged for good, every consumer's grant withdrawn, a secret written to
//! a plain-text file, a password changed at its provider, money spent. The
//! caller reads it before confirming, so it states the effect, what cannot be
//! had back afterwards and who it reaches, what keeps a way back, and how to
//! confirm.
//!
//! Most functionalities declare none. A warning on an ordinary read or a
//! recoverable edit teaches its reader to confirm without reading, which is
//! the one thing a warning exists to prevent; a functionality warns only when
//! its effect is one of the [`Hazard`]s.
//!
//! The same declaration gives the sentence the caller reads before
//! confirming, the `warnings list|show` listing and the documentation page,
//! so none of them can say something the others do not.

use crate::declaration as rules;
use crate::operation::{fill, is_cause_id, is_test_path, text_problems, Operation};
use crate::render::escape;

/// What kind of loss a warning announces.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Hazard {
    /// It removes or rewrites something nothing in the product restores.
    Irreversible,
    /// It puts something else in place of the current state.
    Overwrites,
    /// A person or a program loses access it has now.
    CutsOffAccess,
    /// A secret value leaves the place that protects it.
    ExposesSecret,
    /// It changes a system outside the product, which the product cannot undo.
    ExternalChange,
    /// It spends money.
    CostsMoney,
}

impl Hazard {
    pub const ALL: [Hazard; 6] = [
        Hazard::Irreversible,
        Hazard::Overwrites,
        Hazard::CutsOffAccess,
        Hazard::ExposesSecret,
        Hazard::ExternalChange,
        Hazard::CostsMoney,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Hazard::Irreversible => "irreversible",
            Hazard::Overwrites => "overwrites",
            Hazard::CutsOffAccess => "cuts-off-access",
            Hazard::ExposesSecret => "exposes-secret",
            Hazard::ExternalChange => "external-change",
            Hazard::CostsMoney => "costs-money",
        }
    }

    /// The hazard a name stands for, as `as_str` spells it.
    pub fn parse(name: &str) -> Option<Hazard> {
        Hazard::ALL.into_iter().find(|hazard| hazard.as_str() == name)
    }

    /// What the hazard means, as the documentation page states it.
    pub fn meaning(self) -> &'static str {
        match self {
            Hazard::Irreversible => "removes or rewrites something nothing in the product restores afterwards",
            Hazard::Overwrites => "puts something else in place of the current state; what it replaces is kept only where the warning says",
            Hazard::CutsOffAccess => "a person or a program loses access it has now",
            Hazard::ExposesSecret => "a secret value leaves the place that protects it: a plain-text file, a screen, another person or system",
            Hazard::ExternalChange => "changes a system outside the product, which the product cannot undo",
            Hazard::CostsMoney => "spends money",
        }
    }
}

impl std::fmt::Display for Hazard {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// One thing a functionality does that its caller must know before it runs.
///
/// The four sentences are templates: `{name}` is replaced by the value the
/// warning code supplies, so the caller reads the actual item, host or amount
/// while the catalogue states the shape once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Warning {
    /// Stable within its functionality: lowercase words joined by `-`.
    pub id: &'static str,
    pub hazard: Hazard,
    /// What the functionality is about to do: "{id} and every saved version
    /// of it are removed".
    pub effect: &'static str,
    /// What cannot be had back afterwards, and whom it reaches: "nothing
    /// restores them, and the consumers {consumers} read nothing for it".
    pub consequence: &'static str,
    /// What keeps a way back, done before confirming; where nothing can, it
    /// says so and why.
    pub safeguard: &'static str,
    /// How the caller confirms: the flag, the phrase, the button.
    pub confirm: &'static str,
    /// The real test that shows this warning and proves nothing happens
    /// without the confirmation: `tests/<area>/<file>::<test name>`.
    pub test: &'static str,
}

impl Warning {
    /// The effect and what it costs, as one sentence.
    pub fn sentence(&self, values: &[(&str, &str)]) -> String {
        format!(
            "{}; {}",
            fill(self.effect, values),
            fill(self.consequence, values)
        )
    }

    /// What keeps a way back, with the values filled in.
    pub fn safeguard(&self, values: &[(&str, &str)]) -> String {
        fill(self.safeguard, values)
    }

    /// How to confirm, with the values filled in.
    pub fn confirmation(&self, values: &[(&str, &str)]) -> String {
        fill(self.confirm, values)
    }

    /// What a caller that has not confirmed reads: the warning, that nothing
    /// was done, what keeps a way back and how to go ahead. A functionality
    /// answers this only when it did nothing.
    pub fn unconfirmed(&self, values: &[(&str, &str)]) -> String {
        format!(
            "{}; nothing was done. Before confirming: {}. To go ahead: {}",
            self.sentence(values),
            self.safeguard(values),
            self.confirmation(values)
        )
    }

    /// The anchor of this warning's entry on the warnings page.
    pub fn anchor(&self, operation: &Operation) -> String {
        format!("{}-warning-{}", operation.id.replace('.', "-"), self.id)
    }

    /// Everything wrong with this declaration, each as one sentence.
    pub fn problems(&self) -> Vec<String> {
        let id = self.id;
        let mut problems = Vec::new();
        if !is_cause_id(id) {
            let quoted = escape(id);
            problems.push(fill(
                rules::ID_MALFORMED,
                &[("kind", "warning"), ("quoted_id", &quoted), ("pattern", rules::CAUSE_ID_PATTERN)],
            ));
        }
        problems.extend(text_problems(
            "warning",
            id,
            &[
                ("effect", self.effect),
                ("consequence", self.consequence),
                ("safeguard", self.safeguard),
                ("confirm", self.confirm),
            ],
        ));
        if !is_test_path(self.test) {
            let quoted = escape(self.test);
            problems.push(fill(
                rules::TEST_MALFORMED,
                &[("kind", "warning"), ("id", id), ("quoted_test", &quoted), ("pattern", rules::TEST_PATH_PATTERN)],
            ));
        }
        problems
    }

    fn to_json(self, operation: &Operation, page: &str) -> String {
        format!(
            "{{\"id\":{},\"hazard\":{},\"effect\":{},\"consequence\":{},\"safeguard\":{},\"confirm\":{},\"test\":{},\"doc\":{}}}",
            escape(self.id),
            escape(self.hazard.as_str()),
            escape(self.effect),
            escape(self.consequence),
            escape(self.safeguard),
            escape(self.confirm),
            escape(self.test),
            escape(&format!("{page}#{}", self.anchor(operation))),
        )
    }
}

/// Everything wrong with the warnings one functionality declares: each
/// warning's own problems and a warning declared twice.
pub(crate) fn declaration_problems(operation: &Operation) -> Vec<String> {
    let id = operation.id;
    let mut problems = Vec::new();
    for (index, warning) in operation.warnings.iter().enumerate() {
        if operation.warnings[..index]
            .iter()
            .any(|earlier| earlier.id == warning.id)
        {
            problems.push(fill(
                rules::DECLARED_TWICE,
                &[("operation", id), ("kind", "warning"), ("id", warning.id)],
            ));
        }
        problems.extend(
            warning
                .problems()
                .into_iter()
                .map(|problem| format!("operation {id}: {problem}")),
        );
    }
    problems
}

impl Operation {
    /// The declared warning with this id.
    pub fn warning(&self, id: &str) -> Option<&'static Warning> {
        self.warnings.iter().copied().find(|warning| warning.id == id)
    }

    /// The functionality's warnings as one JSON document, each linked to its
    /// entry on `page`, the product's warnings page.
    pub fn warnings_json(&self, page: &str) -> String {
        let warnings: Vec<String> = self
            .warnings
            .iter()
            .map(|warning| warning.to_json(self, page))
            .collect();
        let entries: Vec<String> = self.entries.iter().map(|entry| escape(entry)).collect();
        format!(
            "{{\"operation\":{},\"entries\":[{}],\"summary\":{},\"warnings\":[{}]}}",
            escape(self.id),
            entries.join(","),
            escape(self.summary),
            warnings.join(",")
        )
    }

    /// The functionality's section of the warnings page, one anchored entry
    /// per warning; empty for a functionality that declares none, because
    /// the page lists only what warns.
    pub fn warnings_markdown(&self) -> String {
        if self.warnings.is_empty() {
            return String::new();
        }
        let entries = if self.entries.is_empty() {
            "run only by the functionalities that use it".to_owned()
        } else {
            self.entries
                .iter()
                .map(|entry| format!("`{entry}`"))
                .collect::<Vec<_>>()
                .join(", ")
        };
        let mut page = format!(
            "## `{}`\n\n{}\n\nStarted through: {entries}. {} declared warning(s).\n",
            self.id,
            self.summary,
            self.warnings.len()
        );
        for warning in self.warnings {
            page.push_str(&format!(
                "\n<a id=\"{anchor}\"></a>\n\n### `{operation}.{id}`\n\n\
                 - **Kind:** `{hazard}`: {meaning}\n\
                 - **What it does:** {effect}\n\
                 - **What cannot be had back:** {consequence}\n\
                 - **Before confirming:** {safeguard}\n\
                 - **To go ahead:** {confirm}\n\
                 - **Test:** `{test}`\n",
                anchor = warning.anchor(self),
                operation = self.id,
                id = warning.id,
                hazard = warning.hazard,
                meaning = warning.hazard.meaning(),
                effect = warning.effect,
                consequence = warning.consequence,
                safeguard = warning.safeguard,
                confirm = warning.confirm,
                test = warning.test,
            ));
        }
        page
    }
}
