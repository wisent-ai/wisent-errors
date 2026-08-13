// Generated from catalogue/codes.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

use std::fmt;

/// How loud this failure is. Derived from the code, never chosen at a call site.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Code {
    Config,
    Auth,
    NotFound,
    RateLimit,
    Timeout,
    InfraDown,
    Unknown,
}

impl Code {
    /// The exit code a retryable failure leaves the process with.
    ///
    /// EX_UNAVAILABLE on every platform this fleet runs on.
    pub const RETRY_EXIT: i32 = 69;

    pub const ALL: &'static [Self] = &[Self::Config, Self::Auth, Self::NotFound, Self::RateLimit, Self::Timeout, Self::InfraDown, Self::Unknown];

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Config => "config",
            Self::Auth => "auth",
            Self::NotFound => "not_found",
            Self::RateLimit => "rate_limit",
            Self::Timeout => "timeout",
            Self::InfraDown => "infra_down",
            Self::Unknown => "unknown",
        }
    }

    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "config" => Some(Self::Config),
            "auth" => Some(Self::Auth),
            "not_found" => Some(Self::NotFound),
            "rate_limit" => Some(Self::RateLimit),
            "timeout" => Some(Self::Timeout),
            "infra_down" => Some(Self::InfraDown),
            "unknown" => Some(Self::Unknown),
            _ => None,
        }
    }

    /// One sentence for the human who just ran the command: ours or theirs?
    pub fn operator_summary(self) -> &'static str {
        match self {
            Self::Config => "our deployment configuration is incomplete or wrong",
            Self::Auth => "the credentials this command used were rejected",
            Self::NotFound => "what the command asked for is not there",
            Self::RateLimit => "an upstream is throttling us",
            Self::Timeout => "an upstream did not answer in time",
            Self::InfraDown => "infrastructure we depend on is unreachable",
            Self::Unknown => "the command failed and we could not attribute the failure",
        }
    }

    /// Worth running the same thing again without changing anything.
    pub fn retryable(self) -> bool {
        matches!(self, Self::RateLimit | Self::Timeout | Self::InfraDown)
    }

    /// Our side is broken, as opposed to the request being wrong.
    pub fn outage(self) -> bool {
        matches!(self, Self::Config | Self::Timeout | Self::InfraDown)
    }

    pub fn severity(self) -> Severity {
        match self {
            Self::Config => Severity::Critical,
            Self::Auth => Severity::Warning,
            Self::NotFound => Severity::Warning,
            Self::RateLimit => Severity::Warning,
            Self::Timeout => Severity::Error,
            Self::InfraDown => Severity::Critical,
            Self::Unknown => Severity::Error,
        }
    }

    /// Classify a status an upstream answered one of our calls with.
    pub fn from_upstream_status(status: u16) -> Self {
        match status {
            401 => Self::Auth,
            403 => Self::Auth,
            404 => Self::NotFound,
            407 => Self::Auth,
            408 => Self::Timeout,
            410 => Self::NotFound,
            429 => Self::RateLimit,
            504 => Self::Timeout,
            _ => {
        if (500..=599).contains(&status) {
            return Self::InfraDown;
        }
                Self::Unknown
            }
        }
    }

    /// The HTTP status a service answers with when this failure reaches its edge.
    pub fn http_status(self) -> u16 {
        match self {
            Self::Config => 503,
            Self::Auth => 401,
            Self::NotFound => 404,
            Self::RateLimit => 429,
            Self::Timeout => 504,
            Self::InfraDown => 503,
            Self::Unknown => 500,
        }
    }

    /// The exit code this failure leaves the process with, given the one the
    /// caller already chose. retryable codes exit with `retry`; every other code keeps the exit code the caller already chose.
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
