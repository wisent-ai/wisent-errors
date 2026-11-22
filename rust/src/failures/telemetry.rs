// Generated from catalogue/failures/telemetry.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

//! This crate's own failures of the telemetry functionalities.

use crate::{Cause, Code, Operation};

pub static TELEMETRY_RECORD: Operation = Operation {
    id: "wisent-errors.telemetry.record",
    entries: &["Telemetry::failure", "Telemetry::command"],
    uses: &[&super::TELEMETRY_STORE],
    summary: "queue one event an installed copy will send, at the level the user chose",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[],
    warnings: &[],
};

pub static TELEMETRY_CONSENT_LEVEL_UNKNOWN: Cause = Cause {
    id: "level-unknown",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "setting the telemetry level to {level}",
    cause: "telemetry knows the levels off, errors and usage",
    observed: "got {level}",
    remedy: "name one of off, errors or usage",
    test: "tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events",
};

pub static TELEMETRY_CONSENT: Operation = Operation {
    id: "wisent-errors.telemetry.consent",
    entries: &["<product> telemetry on|off", "Telemetry::ask", "Telemetry::set_level"],
    uses: &[&super::TELEMETRY_STORE],
    summary: "keep the level of telemetry the user chose",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[&TELEMETRY_CONSENT_LEVEL_UNKNOWN],
    warnings: &[],
};

pub static TELEMETRY_EXPORT_EXPORT_UNWRITABLE: Cause = Cause {
    id: "export-unwritable",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "writing the {count} queued event(s) to {path}",
    cause: "the file could not be written: {why}",
    observed: "{state}; the events stay queued",
    remedy: "name a file in a directory this user can write, as in `{product} telemetry export ./events.json`",
    test: "tests/telemetry/store.rs::telemetry_export_writes_the_queue_as_it_will_be_sent",
};

pub static TELEMETRY_EXPORT: Operation = Operation {
    id: "wisent-errors.telemetry.export",
    entries: &["<product> telemetry export", "Telemetry::export"],
    uses: &[&super::TELEMETRY_STORE],
    summary: "write every queued event to a file the user names, as it would be sent, for a machine with no network",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[&TELEMETRY_EXPORT_EXPORT_UNWRITABLE],
    warnings: &[],
};

pub static TELEMETRY_DELIVER_COLLECTOR_INVALID: Cause = Cause {
    id: "collector-invalid",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading the collector address from {source}",
    cause: "a collector address must be https://, or http:// on a loopback host",
    observed: "{source} holds {address}",
    remedy: "set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it",
    test: "tests/telemetry/delivery/unreached.rs::a_plain_http_collector_is_refused_by_name",
};

pub static TELEMETRY_DELIVER_COLLECTOR_REFUSED: Cause = Cause {
    id: "collector-refused",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "sending event {event} to {collector}",
    cause: "the collector refused HTTP {status}: {answer}",
    observed: "{queued} event(s) stay queued",
    remedy: "the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app {app} in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush",
    test: "tests/telemetry/delivery/reached.rs::an_app_the_collector_does_not_declare_stays_queued_with_its_refusal",
};

pub static TELEMETRY_DELIVER_COLLECTOR_FAILED: Cause = Cause {
    id: "collector-failed",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "sending event {event} to {collector}",
    cause: "the collector failed on its own side, HTTP {status}: {answer}",
    observed: "{queued} event(s) stay queued",
    remedy: "nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `{product} support report`, or from an app's Help → Report a Problem",
    test: "tests/telemetry/delivery/reached.rs::a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure",
};

pub static TELEMETRY_DELIVER_COLLECTOR_UNREACHABLE: Cause = Cause {
    id: "collector-unreachable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "sending event {event} to {collector}",
    cause: "the collector could not be reached: {why}",
    observed: "{queued} event(s) stay queued",
    remedy: "nothing to do: the events are sent on the next flush once the network or the collector is back",
    test: "tests/telemetry/delivery/unreached.rs::an_unreachable_collector_keeps_the_events",
};

pub static TELEMETRY_DELIVER_COLLECTOR_ANSWER_UNREADABLE: Cause = Cause {
    id: "collector-answer-unreadable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "reading the collector's answer to event {event}",
    cause: "the answer is not the collector's {accepted}: {answer}",
    observed: "HTTP {status} from {collector}",
    remedy: "check that {collector} is the Echo app collector, /api/analytics/mobile/collect",
    test: "tests/telemetry/delivery/reached.rs::an_address_that_is_not_a_collector_is_named",
};

pub static TELEMETRY_DELIVER_FLUSH_UNSTARTED: Cause = Cause {
    id: "flush-unstarted",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "starting {program} to send the queued events",
    cause: "the process could not be started: {why}",
    observed: "{queued} event(s) stay queued",
    remedy: "run `{product} telemetry flush` yourself; the events wait until it runs",
    test: "tests/telemetry/delivery/unreached.rs::a_flush_that_cannot_start_is_named",
};

pub static TELEMETRY_DELIVER: Operation = Operation {
    id: "wisent-errors.telemetry.deliver",
    entries: &["<product> telemetry flush", "Telemetry::flush", "Telemetry::spawn_flush"],
    uses: &[&super::TELEMETRY_STORE],
    summary: "send every queued event to the collector and drop the ones it accepted",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[&TELEMETRY_DELIVER_COLLECTOR_INVALID, &TELEMETRY_DELIVER_COLLECTOR_REFUSED, &TELEMETRY_DELIVER_COLLECTOR_FAILED, &TELEMETRY_DELIVER_COLLECTOR_UNREACHABLE, &TELEMETRY_DELIVER_COLLECTOR_ANSWER_UNREADABLE, &TELEMETRY_DELIVER_FLUSH_UNSTARTED],
    warnings: &[],
};

pub static SUPPORT_REPORT_SUPPORT_DESCRIPTION_EMPTY: Cause = Cause {
    id: "support-description-empty",
    code: Code::Refused,
    usage: true,
    exit: None,
    failed: "filing a support report",
    cause: "the report has no description",
    observed: "the description is empty",
    remedy: "say what you were doing and what happened: in an app's Report a Problem window, or with `{product} support report --description \"…\"`",
    test: "tests/telemetry/support.rs::support_report_refuses_what_it_cannot_file_before_anything_is_kept",
};

pub static SUPPORT_REPORT: Operation = Operation {
    id: "wisent-errors.support.report",
    entries: &["<product> support report", "Telemetry::file_report"],
    uses: &[&super::SUPPORT_EXCHANGE, &super::TELEMETRY_STORE],
    summary: "file a support report from this installation and keep the key that reads it back",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[&SUPPORT_REPORT_SUPPORT_DESCRIPTION_EMPTY],
    warnings: &[],
};

pub static SUPPORT_STATUS: Operation = Operation {
    id: "wisent-errors.support.status",
    entries: &["<product> support status", "Telemetry::reports"],
    uses: &[&super::SUPPORT_EXCHANGE, &super::TELEMETRY_STORE],
    summary: "read each report this installation filed back from support: its state and the replies",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[],
    warnings: &[],
};

pub static TELEMETRY_STORE_STORE_UNWRITABLE: Cause = Cause {
    id: "store-unwritable",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "keeping {what} in {path}",
    cause: "the telemetry directory could not be written: {why}",
    observed: "directory {directory}",
    remedy: "make {directory} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME",
    test: "tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events",
};

pub static TELEMETRY_STORE_FILE_UNREADABLE: Cause = Cause {
    id: "file-unreadable",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading {what} from {path}",
    cause: "the file is not what telemetry wrote: {why}",
    observed: "the file holds {bytes} bytes",
    remedy: "answer again, in an app's settings or with `{product} telemetry on|off`, which rewrites it, or remove {path}",
    test: "tests/telemetry/queued/events.rs::telemetry_show_prints_the_queue_each_event_as_declared",
};

pub static TELEMETRY_STORE_FILE_READ_REFUSED: Cause = Cause {
    id: "file-read-refused",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading {what} from {path}",
    cause: "the operating system refused the read, so what the file holds was never looked at",
    observed: "{state}; the operating system answered {error}",
    remedy: "let the user running {product} read it (chmod u+r {path}), or remove {path} so telemetry writes it again",
    test: "tests/telemetry/queued/events.rs::telemetry_show_prints_the_queue_each_event_as_declared",
};

pub static TELEMETRY_STORE: Operation = Operation {
    id: "wisent-errors.telemetry.store",
    entries: &[],
    uses: &[],
    summary: "keep the files telemetry writes (the consent, the installation id, the queue, the last delivery, the keys of support reports) and read them back",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[&TELEMETRY_STORE_STORE_UNWRITABLE, &TELEMETRY_STORE_FILE_UNREADABLE, &TELEMETRY_STORE_FILE_READ_REFUSED],
    warnings: &[],
};

pub static SUPPORT_EXCHANGE_SUPPORT_ADDRESS_INVALID: Cause = Cause {
    id: "support-address-invalid",
    code: Code::Config,
    usage: false,
    exit: None,
    failed: "reading the support address from WISENT_SUPPORT_URL",
    cause: "a support address must be https://, or http:// on a loopback host",
    observed: "WISENT_SUPPORT_URL holds {address}",
    remedy: "set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it",
    test: "tests/telemetry/support.rs::support_report_refuses_what_it_cannot_file_before_anything_is_kept",
};

pub static SUPPORT_EXCHANGE_SUPPORT_REFUSED: Cause = Cause {
    id: "support-refused",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "{doing} at {address}",
    cause: "support refused HTTP {status}: {answer}",
    observed: "{observed}",
    remedy: "the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `{product} support report`",
    test: "tests/telemetry/support.rs::support_report_files_with_the_real_support_and_keeps_its_key",
};

pub static SUPPORT_EXCHANGE_SUPPORT_UNREACHABLE: Cause = Cause {
    id: "support-unreachable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "{doing} at {address}",
    cause: "support could not be reached: {why}",
    observed: "{observed}",
    remedy: "send the report again once the network or support is back, from an app's Report a Problem window or with `{product} support report`",
    test: "tests/telemetry/support.rs::support_report_refuses_what_it_cannot_file_before_anything_is_kept",
};

pub static SUPPORT_EXCHANGE_SUPPORT_ANSWER_UNREADABLE: Cause = Cause {
    id: "support-answer-unreadable",
    code: Code::InfraDown,
    usage: false,
    exit: None,
    failed: "reading support's answer at {address}",
    cause: "the answer is not a support service's: {answer}",
    observed: "HTTP {status}",
    remedy: "check that {address} is a support service's /v1/public/reports",
    test: "tests/telemetry/support.rs::support_report_names_an_address_that_is_not_support",
};

pub static SUPPORT_EXCHANGE: Operation = Operation {
    id: "wisent-errors.support.exchange",
    entries: &[],
    uses: &[],
    summary: "find the support address, send support one request and read its answer",
    docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md",
    causes: &[&SUPPORT_EXCHANGE_SUPPORT_ADDRESS_INVALID, &SUPPORT_EXCHANGE_SUPPORT_REFUSED, &SUPPORT_EXCHANGE_SUPPORT_UNREACHABLE, &SUPPORT_EXCHANGE_SUPPORT_ANSWER_UNREADABLE],
    warnings: &[],
};
