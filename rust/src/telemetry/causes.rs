//! Every way telemetry can fail, declared once, each with the real test that
//! provokes it.

use crate::{Cause, Code, Operation};

const DOCS: &str = "https://github.com/wisent-ai/wisent-errors/blob/main/docs/telemetry.md";

pub static STORE_UNWRITABLE: Cause = Cause {
    id: "store-unwritable",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "keeping {what} in {path}",
    cause: "the telemetry directory could not be written: {why}",
    observed: "directory {directory}",
    remedy:
        "make {directory} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME",
    test: "tests/telemetry/store.rs::an_unwritable_directory_is_named_and_nothing_is_lost_silently",
};

pub static FILE_UNREADABLE: Cause = Cause {
    id: "file-unreadable",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading {what} from {path}",
    cause: "the file is not what telemetry wrote: {why}",
    observed: "the file holds {bytes} bytes",
    remedy: "answer again with `{product} telemetry on|off`, which rewrites it, or remove {path}",
    test: "tests/telemetry/consent.rs::a_damaged_consent_file_is_refused_and_nothing_is_sent",
};

pub static LEVEL_UNKNOWN: Cause = Cause {
    id: "level-unknown",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "setting the telemetry level to {level}",
    cause: "telemetry knows the levels off, errors and usage",
    observed: "got {level}",
    remedy: "name one of off, errors or usage",
    test: "tests/telemetry/consent.rs::an_unknown_level_is_refused",
};

pub static COLLECTOR_INVALID: Cause = Cause {
    id: "collector-invalid",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading the collector address from {source}",
    cause: "a collector address must be https://, or http:// on a loopback host",
    observed: "{source} holds {address}",
    remedy: "set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it",
    test: "tests/telemetry/delivery.rs::a_plain_http_collector_is_refused_by_name",
};

pub static COLLECTOR_REFUSED: Cause = Cause {
    id: "collector-refused",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "sending event {event} to {collector}",
    cause: "the collector refused HTTP {status}: {answer}",
    observed: "{queued} event(s) stay queued",
    remedy: "the answer names what the collector refuses; when it is Unknown mobile analytics app, declare app {app} in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON; the events are sent again on the next flush",
    test: "tests/telemetry/delivery.rs::an_app_the_collector_does_not_declare_stays_queued_with_its_refusal",
};

/// A collector that answered with a server error failed on its own side: the
/// event is not refused, and nothing on the sending machine causes or fixes it.
pub static COLLECTOR_FAILED: Cause = Cause {
    id: "collector-failed",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "sending event {event} to {collector}",
    cause: "the collector failed on its own side, HTTP {status}: {answer}",
    observed: "{queued} event(s) stay queued",
    remedy: "nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `{product} support report`",
    test: "tests/telemetry/delivery.rs::a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure",
};

pub static COLLECTOR_UNREACHABLE: Cause = Cause {
    id: "collector-unreachable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "sending event {event} to {collector}",
    cause: "the collector could not be reached: {why}",
    observed: "{queued} event(s) stay queued",
    remedy: "nothing to do: the events are sent on the next flush once the network or the collector is back",
    test: "tests/telemetry/delivery.rs::an_unreachable_collector_keeps_the_events",
};

pub static COLLECTOR_ANSWER_UNREADABLE: Cause = Cause {
    id: "collector-answer-unreadable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "reading the collector's answer to event {event}",
    cause: "the answer is not the collector's {accepted}: {answer}",
    observed: "HTTP {status} from {collector}",
    remedy: "check that {collector} is the Echo app collector, /api/analytics/mobile/collect",
    test: "tests/telemetry/delivery.rs::an_address_that_is_not_a_collector_is_named",
};

pub static FLUSH_UNSTARTED: Cause = Cause {
    id: "flush-unstarted",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "starting {program} to send the queued events",
    cause: "the process could not be started: {why}",
    observed: "{queued} event(s) stay queued",
    remedy: "run `{product} telemetry flush` yourself; the events wait until it runs",
    test: "tests/telemetry/delivery.rs::a_flush_that_cannot_start_is_named",
};

pub static RECORD: Operation = Operation {
    id: "wisent-errors.telemetry.record",
    entries: &["Telemetry::failure", "Telemetry::command"],
    uses: &[],
    summary: "queue one event an installed copy will send, at the level the user chose",
    docs: DOCS,
    causes: &[&STORE_UNWRITABLE, &FILE_UNREADABLE],
    warnings: &[],
};

pub static CONSENT: Operation = Operation {
    id: "wisent-errors.telemetry.consent",
    entries: &[
        "<product> telemetry on|off",
        "Telemetry::ask",
        "Telemetry::set_level",
    ],
    uses: &[],
    summary: "keep the level of telemetry the user chose",
    docs: DOCS,
    causes: &[&LEVEL_UNKNOWN, &STORE_UNWRITABLE, &FILE_UNREADABLE],
    warnings: &[],
};

pub static DELIVER: Operation = Operation {
    id: "wisent-errors.telemetry.deliver",
    entries: &[
        "<product> telemetry flush",
        "Telemetry::flush",
        "Telemetry::spawn_flush",
    ],
    uses: &[],
    summary: "send every queued event to the collector and drop the ones it accepted",
    docs: DOCS,
    causes: &[
        &COLLECTOR_INVALID,
        &COLLECTOR_REFUSED,
        &COLLECTOR_FAILED,
        &COLLECTOR_UNREACHABLE,
        &COLLECTOR_ANSWER_UNREADABLE,
        &FLUSH_UNSTARTED,
        &STORE_UNWRITABLE,
        &FILE_UNREADABLE,
    ],
    warnings: &[],
};

const SUPPORT_DOCS: &str = "https://github.com/wisent-ai/wisent-errors/blob/main/docs/support.md";

pub static DESCRIPTION_EMPTY: Cause = Cause {
    id: "support-description-empty",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "filing a support report",
    cause: "the report has no description",
    observed: "the description is empty",
    remedy: "say what you were doing and what happened: `{product} support report --description \"…\"`",
    test: "tests/telemetry/support.rs::a_report_without_a_description_is_refused_before_sending",
};

pub static SUPPORT_ADDRESS_INVALID: Cause = Cause {
    id: "support-address-invalid",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading the support address from WISENT_SUPPORT_URL",
    cause: "a support address must be https://, or http:// on a loopback host",
    observed: "WISENT_SUPPORT_URL holds {address}",
    remedy: "set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it",
    test: "tests/telemetry/support.rs::a_plain_http_support_address_is_refused_by_name",
};

pub static SUPPORT_REFUSED: Cause = Cause {
    id: "support-refused",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "{doing} at {address}",
    cause: "support refused HTTP {status}: {answer}",
    observed: "{observed}",
    remedy: "the answer is support's own reason: correct what it names and run the command again",
    test: "tests/telemetry/support.rs::a_report_support_refuses_says_why",
};

pub static SUPPORT_UNREACHABLE: Cause = Cause {
    id: "support-unreachable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "{doing} at {address}",
    cause: "support could not be reached: {why}",
    observed: "{observed}",
    remedy: "run the command again once the network or support is back",
    test: "tests/telemetry/support.rs::an_unreachable_support_files_nothing",
};

pub static SUPPORT_ANSWER_UNREADABLE: Cause = Cause {
    id: "support-answer-unreadable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "reading support's answer at {address}",
    cause: "the answer is not a support service's: {answer}",
    observed: "HTTP {status}",
    remedy: "check that {address} is a support service's /v1/public/reports",
    test: "tests/telemetry/support.rs::an_address_that_is_not_support_is_named",
};

pub static REPORT: Operation = Operation {
    id: "wisent-errors.support.report",
    entries: &["<product> support report", "Telemetry::file_report"],
    uses: &[],
    summary: "file a support report from this installation and keep the key that reads it back",
    docs: SUPPORT_DOCS,
    causes: &[
        &DESCRIPTION_EMPTY,
        &SUPPORT_ADDRESS_INVALID,
        &SUPPORT_REFUSED,
        &SUPPORT_UNREACHABLE,
        &SUPPORT_ANSWER_UNREADABLE,
        &STORE_UNWRITABLE,
        &FILE_UNREADABLE,
    ],
    warnings: &[],
};

pub static STATUS: Operation = Operation {
    id: "wisent-errors.support.status",
    entries: &["<product> support status", "Telemetry::reports"],
    uses: &[],
    summary: "read each report this installation filed back from support: its state and the replies",
    docs: SUPPORT_DOCS,
    causes: &[
        &SUPPORT_ADDRESS_INVALID,
        &SUPPORT_REFUSED,
        &SUPPORT_UNREACHABLE,
        &SUPPORT_ANSWER_UNREADABLE,
        &FILE_UNREADABLE,
    ],
    warnings: &[],
};

/// Every telemetry and support functionality, for a product's `errors list`.
pub fn operations() -> [&'static Operation; 5] {
    [&RECORD, &CONSENT, &DELIVER, &REPORT, &STATUS]
}
