// Render the Rust vocabulary from the generator's prepared catalogue.

const rustName = (code) => code.split('_').map((part) => part[0].toUpperCase() + part.slice(1)).join('');

export function rust({ catalogue, codes, exact, ranges, fallback, banner }) {
  const variants = codes.map((entry) => `    ${rustName(entry.code)},`).join('\n');
  const asStr = codes.map((entry) => `            Self::${rustName(entry.code)} => "${entry.code}",`).join('\n');
  const parse = codes.map((entry) => `            "${entry.code}" => Some(Self::${rustName(entry.code)}),`).join('\n');
  const summary = codes.map((entry) => `            Self::${rustName(entry.code)} => "${entry.operator_summary}",`).join('\n');
  const retryable = codes.filter((entry) => entry.retryable).map((entry) => `Self::${rustName(entry.code)}`).join(' | ');
  const outage = codes.filter((entry) => entry.outage).map((entry) => `Self::${rustName(entry.code)}`).join(' | ');
  const severity = codes.map((entry) => `            Self::${rustName(entry.code)} => Severity::${entry.severity[0].toUpperCase() + entry.severity.slice(1)},`).join('\n');
  const statusArms = exact.map(([status, code]) => `            ${status} => Self::${rustName(code)},`).join('\n');
  const httpStatus = codes.map((entry) => `            Self::${rustName(entry.code)} => ${entry.http_status},`).join('\n');
  const rangeArms = ranges
    .map((range) => `        if (${range.from}..=${range.to}).contains(&status) {\n            return Self::${rustName(range.code)};\n        }`)
    .join('\n');

  return `${banner('//')}

use std::fmt;

/// How loud this failure is. Derived from the code, never chosen at a call site.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Warning,
    Error,
    Critical,
}

impl Severity {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Warning => "warning",
            Self::Error => "error",
            Self::Critical => "critical",
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// The fleet's whole failure vocabulary.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq, PartialOrd, Ord)]
pub enum Code {
${variants}
}

impl Code {
    /// The exit code a retryable failure leaves the process with.
    ///
    /// ${catalogue.exit_code.retry_name} on every platform this fleet runs on.
    pub const RETRY_EXIT: i32 = ${catalogue.exit_code.retry};

    pub const ALL: &'static [Self] = &[${codes.map((entry) => `Self::${rustName(entry.code)}`).join(', ')}];

    pub fn as_str(self) -> &'static str {
        match self {
${asStr}
        }
    }

    pub fn parse(text: &str) -> Option<Self> {
        match text {
${parse}
            _ => None,
        }
    }

    /// The code when the catalogue knows this text, otherwise the fallback.
    ///
    /// Never fails. Three products wrote this coercion by hand during their
    /// migration, which is the duplication this package exists to remove.
    pub fn or_fallback(text: &str) -> Self {
        match Self::parse(text) {
            Some(code) => code,
            None => Self::${rustName(fallback)},
        }
    }

    /// One sentence for the human who just ran the command: ours or theirs?
    pub fn operator_summary(self) -> &'static str {
        match self {
${summary}
        }
    }

    /// Worth running the same thing again without changing anything.
    pub fn retryable(self) -> bool {
        matches!(self, ${retryable})
    }

    /// Our side is broken, as opposed to the request being wrong.
    pub fn outage(self) -> bool {
        matches!(self, ${outage})
    }

    pub fn severity(self) -> Severity {
        match self {
${severity}
        }
    }

    /// Classify a status an upstream answered one of our calls with.
    pub fn from_upstream_status(status: u16) -> Self {
        match status {
${statusArms}
            _ => {
${rangeArms}
                Self::${rustName(fallback)}
            }
        }
    }

    /// The HTTP status a service answers with when this failure reaches its edge.
    pub fn http_status(self) -> u16 {
        match self {
${httpStatus}
        }
    }

    /// The exit code this failure leaves the process with, given the one the
    /// caller already chose. ${catalogue.exit_code.rule}.
    pub fn exit_code(self, chosen: i32) -> i32 {
        if self.retryable() {
            Self::RETRY_EXIT
        } else {
            chosen
        }
    }
}

impl fmt::Display for Code {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}
`;
}

