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
use std::fmt;

mod codes;

pub use codes::{Code, Severity};

/// Identifiers a reader needs to find the subject: a host, a subscription, a job.
pub type Context = BTreeMap<String, String>;

/// This crate's own bound. A product's bound is the product's to choose.
pub const DETAIL_LIMIT: usize = 2000;

/// Trim a detail to a bound, on a word edge when one is near the cut.
///
/// The limit is an argument because the width is a product's own decision --
/// stado and probierz keep 300, wisent-customer-support 400, wisent-tools 500 --
/// while the rule for how to cut is the thing that was written six times.
pub fn trim_detail(text: &str, limit: usize) -> String {
    let value = text.trim();
    if value.chars().count() <= limit {
        return value.to_owned();
    }
    let cut: String = value.chars().take(limit).collect();
    match cut.rfind(' ') {
        Some(edge) if edge > limit.saturating_sub(24) => cut[..edge].trim_end().to_owned(),
        _ => cut.trim_end().to_owned(),
    }
}

/// Why an envelope could not be built. Rejecting it here is the point: an
/// envelope with an unparseable failure point or an empty detail is worse than
/// none, because it looks like a report.
#[derive(Debug, PartialEq, Eq)]
pub enum Invalid {
    FailurePoint(String),
    Empty(&'static str),
}

impl fmt::Display for Invalid {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::FailurePoint(point) => write!(
                formatter,
                "failure_point {point:?} is not a dotted lowercase path"
            ),
            Self::Empty(field) => write!(formatter, "{field} must not be empty"),
        }
    }
}

impl std::error::Error for Invalid {}

/// One failure, in the shape every Wisent component reports.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Failure {
    pub failure_point: String,
    pub code: Code,
    pub service: String,
    pub impact: Option<String>,
    pub detail: Option<String>,
    pub cause: Option<Box<Failure>>,
    pub context: Context,
}

/// A dotted lowercase path: digits and single separators inside each segment.
///
/// The depth carries no meaning. This checked for exactly three segments until
/// the migrations reached real registries -- stado's own ids run from `cli` to
/// `cli.host.user.create` -- and a rule that refuses what five products emit is
/// this crate being wrong.
fn valid_failure_point(point: &str) -> bool {
    let mut segments = 0;
    for segment in point.split('.') {
        segments += 1;
        let bytes = segment.as_bytes();
        let Some(&first) = bytes.first() else {
            return false;
        };
        if !first.is_ascii_lowercase() {
            return false;
        }
        if !segment
            .chars()
            .all(|character| character.is_ascii_lowercase() || character.is_ascii_digit() || character == '-' || character == '_')
        {
            return false;
        }
        if segment.ends_with('-') || segment.ends_with('_') || segment.contains("--") || segment.contains("__") {
            return false;
        }
    }
    segments >= 1 && !point.is_empty()
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
        let failure_point = failure_point.into().trim().to_owned();
        if !valid_failure_point(&failure_point) {
            return Err(Invalid::FailurePoint(failure_point));
        }
        let service = service.into().trim().to_owned();
        if service.is_empty() {
            return Err(Invalid::Empty("service"));
        }
        Ok(Self {
            failure_point,
            code,
            service,
            impact: None,
            detail: None,
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
        } else if !valid_failure_point(&point) {
            notes.push(("wisent_errors.failure_point", "malformed"));
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

    /// The reason the layer below gave, verbatim and bounded.
    pub fn detail(mut self, detail: impl Into<String>) -> Self {
        let value = trim_detail(&detail.into(), DETAIL_LIMIT);
        self.detail = if value.is_empty() { None } else { Some(value) };
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

    /// The envelope as JSON, with keys in the schema's order so two runtimes
    /// produce the same bytes and a conformance test can compare them.
    pub fn to_json(&self) -> String {
        let mut out = String::new();
        out.push('{');
        push_pair(&mut out, "failure_point", &self.failure_point, true);
        push_pair(&mut out, "error_code", self.code.as_str(), false);
        push_pair(&mut out, "service", &self.service, false);
        push_optional(&mut out, "impact", self.impact.as_deref());
        push_pair(&mut out, "severity", self.severity().as_str(), false);
        out.push_str(&format!(",\"retryable\":{}", self.retryable()));
        out.push_str(&format!(",\"outage\":{}", self.outage()));
        push_optional(&mut out, "detail", self.detail.as_deref());
        if let Some(cause) = &self.cause {
            out.push_str(",\"cause\":");
            out.push_str(&cause.to_json());
        }
        if !self.context.is_empty() {
            out.push_str(",\"context\":{");
            for (index, (key, value)) in self.context.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                out.push_str(&escape(key));
                out.push(':');
                out.push_str(&escape(value));
            }
            out.push('}');
        }
        out.push('}');
        out
    }

    /// One line for a human, and the envelope for everything else.
    pub fn render(&self) -> String {
        let retry = if self.retryable() {
            "; retry later"
        } else {
            "; retrying will not help"
        };
        let whose = if self.outage() {
            "our failure"
        } else {
            "the request or its credentials"
        };
        format!(
            "{} — {whose}{retry} {}",
            self.code.operator_summary(),
            self.to_json()
        )
    }

    /// Flatten the cause chain, outermost first, for a reader in a hurry.
    pub fn chain(&self) -> Vec<String> {
        let mut rows = Vec::new();
        let mut node = Some(self);
        while let Some(current) = node {
            rows.push(format!(
                "{} [{}] {}",
                current.failure_point,
                current.code.as_str(),
                current.detail.as_deref().unwrap_or("-")
            ));
            node = current.cause.as_deref();
        }
        rows
    }
}

impl fmt::Display for Failure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.render())
    }
}

impl std::error::Error for Failure {}

/// An absent optional is written as `null`, never dropped: a stable key set is
/// what makes these lines queryable, and a missing key reads as a different
/// fact from a key that says nothing was said.
fn push_optional(out: &mut String, key: &str, value: Option<&str>) {
    match value {
        Some(text) => push_pair(out, key, text, false),
        None => out.push_str(&format!(",{}:null", escape(key))),
    }
}

fn push_pair(out: &mut String, key: &str, value: &str, first: bool) {
    if !first {
        out.push(',');
    }
    out.push_str(&escape(key));
    out.push(':');
    out.push_str(&escape(value));
}

/// Minimal JSON string escaping. The crate deliberately carries no serde
/// dependency: a package every product must adopt has to be cheap to adopt.
fn escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            control if control < ' ' => out.push_str(&format!("\\u{:04x}", control as u32)),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derived_fields_cannot_be_chosen_at_the_call_site() {
        let failure = Failure::new("brama.dispatch.bounded-rotation", Code::RateLimit, "brama")
            .expect("valid")
            .impact("one model request")
            .detail("all bounded 'codex' credentials unavailable for agent");
        assert!(failure.retryable());
        assert!(!failure.outage());
        assert_eq!(failure.severity(), Severity::Warning);
    }

    #[test]
    fn a_single_segment_failure_point_is_accepted() {
        // stado's ids come from the clap subcommand path and `cli` is one of them.
        let point = Failure::new("cli", Code::Unknown, "stado").expect("valid");
        assert_eq!(point.failure_point, "cli");
    }

    #[test]
    fn an_empty_segment_is_still_refused() {
        let refused = Failure::new("brama..dispatch", Code::Unknown, "brama");
        assert!(matches!(refused, Err(Invalid::FailurePoint(_))));
    }

    #[test]
    fn an_absent_detail_is_null_rather_than_missing() {
        let quiet = Failure::new("accounts.create", Code::NotFound, "growth-tactics").expect("valid");
        assert_eq!(quiet.detail, None);
        assert!(quiet.to_json().contains("\"detail\":null"));
        assert!(quiet.to_json().contains("\"impact\":null"));
    }

    #[test]
    fn reporting_a_failure_never_fails() {
        let salvaged = Failure::or_fallback("Not A Point", Code::Unknown, "");
        assert_eq!(salvaged.failure_point, "Not A Point");
        assert_eq!(salvaged.service, "unknown");
        assert_eq!(
            salvaged.context.get("wisent_errors.failure_point").map(String::as_str),
            Some("malformed")
        );
        assert_eq!(
            salvaged.context.get("wisent_errors.service").map(String::as_str),
            Some("absent")
        );
    }

    #[test]
    fn an_off_catalogue_code_becomes_the_fallback() {
        assert_eq!(Code::or_fallback("no_such_code"), Code::Unknown);
        assert_eq!(Code::or_fallback("rate_limit"), Code::RateLimit);
    }

    #[test]
    fn a_products_own_bound_is_the_products_to_choose() {
        let long = "x".repeat(600);
        assert_eq!(trim_detail(&long, 500).chars().count(), 500);
        assert_eq!(trim_detail("short", 500), "short");
    }

    #[test]
    fn the_chain_keeps_the_reason_the_bottom_layer_gave() {
        let vault = Failure::new("skarbiec.authority.redeem", Code::Auth, "skarbiec")
            .expect("valid")
            .impact("one capability redemption")
            .detail("redemption denied: no value at provider:codex:sub#value");
        let provider = Failure::new("brama.gateway.oauth-refresh", Code::Auth, "brama")
            .expect("valid")
            .impact("one credential refresh")
            .detail("invalid_grant -- Refresh token not found or invalid")
            .caused_by(vault);
        let caller = Failure::new("brama.dispatch.bounded-rotation", Code::RateLimit, "brama")
            .expect("valid")
            .impact("one model request")
            .detail("all bounded 'codex' credentials unavailable for agent")
            .caused_by(provider);

        let chain = caller.chain();
        assert_eq!(chain.len(), 3);
        assert!(chain[2].contains("redemption denied"));
    }


    #[test]
    fn server_errors_are_never_not_found() {
        assert_eq!(Code::from_upstream_status(503), Code::InfraDown);
        assert_eq!(Code::from_upstream_status(404), Code::NotFound);
        assert_eq!(Code::from_upstream_status(429), Code::RateLimit);
        assert_eq!(Code::from_upstream_status(418), Code::Unknown);
    }
}
