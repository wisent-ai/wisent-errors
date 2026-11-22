//! What a refusal of a declared cause is to the operator: the one class its
//! printed line, its log line, the `errors show` listing and its catalogue
//! page all name. A usage refusal is the command line's own, whatever code
//! its cause carries: most usage causes declare `config` or `refused`, and a
//! page or a log naming that code told whoever read it that the deployment
//! was misconfigured or a policy refused, when the command line was mistyped.

use super::cause::Cause;
use crate::{Code, Severity};

/// What a usage refusal is, in the words its printed line and its log line
/// open with: the command line named something the command cannot use, so
/// the line itself is corrected, and nothing outside it failed.
pub const USAGE_SUMMARY: &str = "the command line names something this command cannot use";

/// A refusal's class: usage, or the code it states.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Class {
    /// The request was refused for its own form and exits
    /// [`Code::USAGE_EXIT`]: the caller corrects the command line.
    Usage,
    /// The code the failure states.
    Code(Code),
}

impl Class {
    /// A declared cause's class: usage when the cause refuses the request for
    /// its own form, whatever code it carries, otherwise its code.
    pub fn of(cause: &Cause) -> Self {
        if cause.usage {
            Self::Usage
        } else {
            Self::Code(cause.code)
        }
    }

    /// Its name, as a refusal prints it and a log line's `error_code`
    /// carries it: `usage`, or the code's own name.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Usage => "usage",
            Self::Code(code) => code.as_str(),
        }
    }

    /// Whether running the same command again can help: never for a command
    /// line that names something the command cannot use.
    pub fn retryable(self) -> bool {
        match self {
            Self::Usage => false,
            Self::Code(code) => code.retryable(),
        }
    }

    /// How loud it is: a usage refusal at the severity the catalogue gives a
    /// request it refuses (`warning`).
    pub fn severity(self) -> Severity {
        match self {
            Self::Usage => Severity::Warning,
            Self::Code(code) => code.severity(),
        }
    }

    /// What happened, in the words a printed line and a log line open with.
    pub fn summary(self) -> &'static str {
        match self {
            Self::Usage => USAGE_SUMMARY,
            Self::Code(code) => code.operator_summary(),
        }
    }
}

impl std::fmt::Display for Class {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.as_str())
    }
}
