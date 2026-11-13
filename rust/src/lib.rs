//! The failure envelope, for Rust components.
//!
//! Two things only: build an envelope whose derived fields cannot be wrong, and
//! render it so a reader can find the source. Everything a caller decides --
//! where it broke, what the layer below said, which subject it concerns -- is an
//! argument. Everything derivable from the code is derived.
//!
//! The `cause` chain is the field this crate exists for. A gateway refusing a
//! request because a provider refused a token because a vault refused a read is
//! three failures; reporting only the outermost is how a day goes into finding
//! what the innermost already said.

use std::collections::BTreeMap;

mod codes;
pub mod declaration;
pub mod failures;
mod invalid;
pub mod operation;
#[path = "output/render.rs"]
mod render;
#[path = "output/warning.rs"]
pub mod warning;

#[cfg(feature = "cli-output")]
#[path = "output/cli_output.rs"]
pub mod cli_output;

#[cfg(feature = "telemetry")]
pub mod telemetry;

#[cfg(feature = "diagnosis")]
pub mod diagnosis;

pub use codes::{Code, GenericSentence, Severity, FAILURE_POINT_PATTERN, GENERIC_SENTENCES};
pub use invalid::Invalid;
pub use operation::{catalogue_problems, Cause, Operation};
pub use warning::{Hazard, Warning};

/// Identifiers a reader needs to find the subject: a host, a subscription, a job.
pub type Context = BTreeMap<String, String>;

/// One failure, in the shape every Wisent component reports.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Failure {
    pub failure_point: String,
    pub code: Code,
    pub service: String,
    pub impact: Option<String>,
    pub detail: Option<String>,
    /// What would fix it, for the person reading the failure: the command to
    /// run, the declaration to change, the dependency to bring back. Absent
    /// only where nothing the reader does can help.
    pub remedy: Option<String>,
    pub cause: Option<Box<Failure>>,
    pub context: Context,
}

/// A dotted lowercase path: digits and single separators inside each segment
/// ([`FAILURE_POINT_PATTERN`]).
///
/// The depth carries no meaning. This checked for exactly three segments until
/// the migrations reached real registries -- stado's own ids run from `cli` to
/// `cli.host.user.create` -- and a rule that refuses what five products emit is
/// this crate being wrong.
fn valid_failure_point(point: &str) -> bool {
    invalid::point_flaw(point).is_none()
}

impl Failure {
    /// Build an envelope.
    ///
    /// `detail` and `impact` are `Option` and serialize as `null` when absent: a
    /// stable key set is what makes these lines queryable in a log store, three
    /// products in this fleet have no impact axis at all, and a call site that
    /// knows its code exactly may have no layer below to quote. Making either
    /// mandatory buys `impact: "unknown"`, a worse lie than an absent value.
    ///
    /// Fails on anything malformed. Inside an error path, where returning an
    /// error destroys the diagnosis being carried, use [`Failure::or_fallback`].
    pub fn new(
        failure_point: impl Into<String>,
        code: Code,
        service: impl Into<String>,
    ) -> Result<Self, Invalid> {
        let given = failure_point.into();
        let service = service.into();
        let failure_point = given.trim().to_owned();
        if !valid_failure_point(&failure_point) {
            return Err(Invalid::FailurePoint { given, service });
        }
        let named = service.trim().to_owned();
        if named.is_empty() {
            return Err(Invalid::Empty {
                field: "service",
                given: service,
                failure_point,
            });
        }
        let service = named;
        Ok(Self {
            failure_point,
            code,
            service,
            impact: None,
            detail: None,
            remedy: None,
            cause: None,
            context: Context::new(),
        })
    }

    /// An envelope that is always produced, whatever it was handed.
    ///
    /// Reporting a failure must not itself fail: an error path that returns an
    /// error instead of a report takes the diagnosis with it, which is how hours
    /// of an outage end up with no record of why. An unparseable point is kept
    /// verbatim -- an operator still needs it -- and the violation is recorded in
    /// `context` under a `wisent_errors.` key, so the defect travels in the data.
    pub fn or_fallback(
        failure_point: impl Into<String>,
        code: Code,
        service: impl Into<String>,
    ) -> Self {
        let mut notes: Vec<(&'static str, &'static str)> = Vec::new();
        let mut point = failure_point.into().trim().to_owned();
        if point.is_empty() {
            point = "unknown".to_owned();
            notes.push(("wisent_errors.failure_point", "absent"));
        } else if let Some(flaw) = invalid::point_flaw(&point) {
            notes.push(("wisent_errors.failure_point", "malformed"));
            notes.push(("wisent_errors.failure_point_cause", flaw.cause.id));
        }
        let mut service = service.into().trim().to_owned();
        if service.is_empty() {
            service = "unknown".to_owned();
            notes.push(("wisent_errors.service", "absent"));
        }
        let mut failure = Self {
            failure_point: point,
            code,
            service,
            impact: None,
            detail: None,
            remedy: None,
            cause: None,
            context: Context::new(),
        };
        for (key, value) in notes {
            failure = failure.with_context(key, value);
        }
        failure
    }

    /// What the caller loses. Absent where a product has no impact axis.
    pub fn impact(mut self, impact: impl Into<String>) -> Self {
        let value = impact.into().trim().to_owned();
        self.impact = if value.is_empty() { None } else { Some(value) };
        self
    }

    /// The reason the layer below gave, verbatim and whole; only the
    /// whitespace around it goes.
    pub fn detail(mut self, detail: impl Into<String>) -> Self {
        let value = detail.into().trim().to_owned();
        self.detail = if value.is_empty() { None } else { Some(value) };
        self
    }

    /// What would fix it, whole; only the whitespace around it goes.
    pub fn remedy(mut self, remedy: impl Into<String>) -> Self {
        let value = remedy.into().trim().to_owned();
        self.remedy = if value.is_empty() { None } else { Some(value) };
        self
    }

    /// The failure underneath this one.
    pub fn caused_by(mut self, cause: Self) -> Self {
        self.cause = Some(Box::new(cause));
        self
    }

    pub fn with_context(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.context.insert(key.into(), value.into());
        self
    }

    pub fn severity(&self) -> Severity {
        self.code.severity()
    }

    pub fn retryable(&self) -> bool {
        self.code.retryable()
    }

    pub fn outage(&self) -> bool {
        self.code.outage()
    }
}
