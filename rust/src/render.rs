//! JSON serialization, human-readable rendering and cause-chain projection.

use crate::Failure;
use std::fmt;

impl Failure {
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
