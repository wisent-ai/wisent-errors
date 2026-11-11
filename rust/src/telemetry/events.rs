//! Every event the reporter can send, with the consent it needs and each
//! property it carries: the one declaration the queue takes events from, a
//! product's privacy page shows (`<product> telemetry events`), and that
//! page's check holds it to. An event that is not declared here cannot be
//! queued, because `Telemetry::queue` takes an `&'static Event`.

use super::Level;

/// One kind of event, as it goes to the collector.
#[derive(Debug)]
pub struct Event {
    /// The collector's `eventName`.
    pub name: &'static str,
    /// The least consent under which it is queued.
    pub consent: Level,
    /// What it says, in one sentence, for the privacy page.
    pub summary: &'static str,
    /// Every key of its `properties`, and nothing else.
    pub properties: &'static [&'static str],
}

pub static FAILURE: Event = Event {
    name: "failure",
    consent: Level::Errors,
    summary: "a command or screen failed: where, the declared cause, the sentence and the fix it showed, without your home directory or this machine's name",
    properties: &[
        "failure_point", "error_code", "severity", "retryable", "outage", "service", "impact", "detail",
        "remedy", "cause_id", "context", "causes",
    ],
};

pub static CLI_COMMAND: Event = Event {
    name: "cli.command",
    consent: Level::Usage,
    summary:
        "a command finished: its name only, never its arguments, how it exited and how long it took",
    properties: &["command", "exit_status", "duration_ms"],
};

pub static REPEAT_FAILURE: Event = Event {
    name: "frustration.repeat_failure",
    consent: Level::Errors,
    summary: "the same failure happened again: how many times in a row and the seconds since the previous one",
    properties: &["failure_point", "consecutive", "seconds_since_previous"],
};

pub static USAGE_LOOP: Event = Event {
    name: "frustration.usage_loop",
    consent: Level::Usage,
    summary: "the same command was refused as a usage error again: its name, how many times in a row and the seconds since the previous one",
    properties: &["command", "consecutive", "seconds_since_previous"],
};

pub static HELP_AFTER_FAILURE: Event = Event {
    name: "frustration.help_after_failure",
    consent: Level::Usage,
    summary: "help was asked for after a failure: the command it was asked about, which failure came before it and how long before",
    properties: &["command", "failure_point", "seconds_since_failure"],
};

/// Every event, in the order the privacy page lists them.
pub static EVENTS: &[&Event] = &[
    &FAILURE,
    &CLI_COMMAND,
    &REPEAT_FAILURE,
    &USAGE_LOOP,
    &HELP_AFTER_FAILURE,
];
