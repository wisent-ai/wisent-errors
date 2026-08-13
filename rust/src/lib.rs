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

const DETAIL_LIMIT: usize = 2000;

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
                "failure_point {point:?} is not <service>.<surface>.<operation>"
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
    pub impact: String,
    pub detail: String,
    pub cause: Option<Box<Failure>>,
    pub context: Context,
}

/// Three dotted segments, lowercase, digits and single separators inside each.
/// Validated rather than enumerated: a closed list of failure points would be
/// stale the day after it was written.
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
    segments == 3
}

impl Failure {
    /// Build an envelope.
    ///
    /// `detail` is required on purpose. A failure reported without the reason
    /// the layer below gave is the defect this crate exists to prevent, and
    /// making it optional is how that defect gets written again.
    pub fn new(
        failure_point: impl Into<String>,
        code: Code,
        service: impl Into<String>,
        impact: impl Into<String>,
        detail: impl Into<String>,
    ) -> Result<Self, Invalid> {
        let failure_point = failure_point.into().trim().to_owned();
        if !valid_failure_point(&failure_point) {
            return Err(Invalid::FailurePoint(failure_point));
        }
        let service = service.into().trim().to_owned();
        if service.is_empty() {
            return Err(Invalid::Empty("service"));
        }
        let impact = impact.into().trim().to_owned();
        if impact.is_empty() {
            return Err(Invalid::Empty("impact"));
        }
        let detail = detail.into().trim().chars().take(DETAIL_LIMIT).collect::<String>();
        if detail.is_empty() {
            return Err(Invalid::Empty("detail"));
        }
        Ok(Self {
            failure_point,
            code,
            service,
            impact,
            detail,
            cause: None,
            context: Context::new(),
        })
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
        push_pair(&mut out, "impact", &self.impact, false);
        push_pair(&mut out, "severity", self.severity().as_str(), false);
        out.push_str(&format!(",\"retryable\":{}", self.retryable()));
        out.push_str(&format!(",\"outage\":{}", self.outage()));
        push_pair(&mut out, "detail", &self.detail, false);
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
                current.detail
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
        let failure = Failure::new(
            "brama.dispatch.bounded-rotation",
            Code::RateLimit,
            "brama",
            "one model request",
            "all bounded 'codex' credentials unavailable for agent",
        )
        .expect("valid");
        assert!(failure.retryable());
        assert!(!failure.outage());
        assert_eq!(failure.severity(), Severity::Warning);
    }

    #[test]
    fn a_failure_point_with_two_segments_is_refused() {
        let refused = Failure::new("brama.dispatch", Code::Unknown, "brama", "impact", "detail");
        assert!(matches!(refused, Err(Invalid::FailurePoint(_))));
    }

    #[test]
    fn an_empty_detail_is_refused() {
        let refused = Failure::new("brama.gateway.oauth-refresh", Code::Auth, "brama", "impact", "   ");
        assert_eq!(refused, Err(Invalid::Empty("detail")));
    }

    #[test]
    fn the_chain_keeps_the_reason_the_bottom_layer_gave() {
        let vault = Failure::new(
            "skarbiec.authority.redeem",
            Code::Auth,
            "skarbiec",
            "one capability redemption",
            "redemption denied: no value at provider:codex:sub#value",
        )
        .expect("valid");
        let provider = Failure::new(
            "brama.gateway.oauth-refresh",
            Code::Auth,
            "brama",
            "one credential refresh",
            "invalid_grant -- Refresh token not found or invalid",
        )
        .expect("valid")
        .caused_by(vault);
        let caller = Failure::new(
            "brama.dispatch.bounded-rotation",
            Code::RateLimit,
            "brama",
            "one model request",
            "all bounded 'codex' credentials unavailable for agent",
        )
        .expect("valid")
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
