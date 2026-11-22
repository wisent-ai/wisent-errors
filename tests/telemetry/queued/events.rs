//! `wisent-errors telemetry events`, the declaration of every event the
//! reporter can send, and `wisent-errors --product <file> telemetry show`,
//! the queue as it will be sent: every queued event is one the declaration
//! lists, carrying exactly the properties it declares, so the list a
//! product's privacy page shows is what is sent.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry queued::events::
//!
//! - Rule 4: both commands run as the crate's command line, a process:
//!   `Case::run` and `Case::bare` (tests/telemetry/main.rs) start
//!   `env!("CARGO_BIN_EXE_wisent-errors")` with `std::process::Command`,
//!   its environment cleared, and nothing else stands between this file
//!   and the binary. Each kind of event is produced by the command's own
//!   `telemetry failure`, `telemetry command` and `telemetry help`, the
//!   commands a product reports through, in the store of the case, never
//!   written by hand. No case calls the library.
//! - Rule 5: what `show` prints is held to the event files on disk:
//!   `Case::queued` (main.rs) lists `<WISENT_TELEMETRY_HOME>/queue/*.json`
//!   with `std::fs::read_dir` and parses each file, so the comparison is
//!   of the store on disk against stdout, read back after each step. A
//!   refused `show` prints nothing, exits with the cause's status, says the
//!   whole three-line refusal, and leaves the damaged or unreadable event
//!   file as it was; `events` writes nothing.
//! - Rule 9: the `events` document, every event's properties and every
//!   refusal but the two of a damaged and an unreadable queued event were
//!   read from live runs of `wisent-errors` built from this tree
//!   (2026-11-21 18:43, features cli-output, telemetry and diagnosis),
//!   probed by hand with `env -i`, HOME and TMPDIR under target/probe, and
//!   that build's run of this target passed. Those two are causes
//!   (`queued-event-unreadable`, `queued-event-read-refused`) that replaced
//!   the store's general ones after that build, whose fix told the user to
//!   answer the consent again, which never writes a queued event. They are
//!   the declared sentences read from catalogue/failures/telemetry.json, and
//!   the Swift command line said them live
//!   (tests/telemetry/swift/DeliveryTests.swift). The event names and
//!   `example-product.pairs.import` are the case's own fictional product
//!   and failure point, given to the command, not answers pinned from it.

use std::collections::BTreeSet;
use std::os::unix::fs::PermissionsExt;

use serde_json::{json, Value};

use crate::{cause, refusal, Case, FAILURE, PRODUCT, USAGE};

/// `telemetry events` needs no product and writes nothing; an operand is
/// more than it reads.
#[test]
fn telemetry_events_lists_every_event_a_product_can_send() {
    let mut case = Case::new("events");
    let listed = case.bare(&["telemetry", "events"]).succeeded();
    assert_eq!(
        listed,
        json!([
            {
                "name": "failure",
                "consent": "errors",
                "summary": "a command or screen failed: where, the declared cause, the sentence and the fix it showed, without your home directory or this machine's name",
                "properties": ["failure_point", "error_code", "severity", "retryable", "outage", "service", "impact", "detail", "remedy", "cause_id", "context", "causes"],
            },
            {
                "name": "cli.command",
                "consent": "usage",
                "summary": "a command finished: its name only, never its arguments, how it exited and how long it took",
                "properties": ["command", "exit_status", "duration_ms"],
            },
            {
                "name": "frustration.repeat_failure",
                "consent": "errors",
                "summary": "the same failure happened again: how many times in a row and the seconds since the previous one",
                "properties": ["failure_point", "consecutive", "seconds_since_previous"],
            },
            {
                "name": "frustration.usage_loop",
                "consent": "usage",
                "summary": "the same command was refused as a usage error again: its name, how many times in a row and the seconds since the previous one",
                "properties": ["command", "consecutive", "seconds_since_previous"],
            },
            {
                "name": "frustration.help_after_failure",
                "consent": "usage",
                "summary": "help was asked for after a failure: the command it was asked about, which failure came before it and how long before",
                "properties": ["command", "failure_point", "seconds_since_failure"],
            },
        ])
    );
    assert!(!case.state.exists(), "events writes nothing: {}", case.state.display());

    case.bare(&["telemetry", "events", "failure"]).refused(USAGE, &refusal(
        "reading the operands of `wisent-errors telemetry events`: the command takes no operand, and \"failure\" is more than it reads; observed: its operands were [\"failure\"]",
        "drop \"failure\", or quote an operand that holds spaces as one word, as in `wisent-errors telemetry events`",
        "wisent_errors.command.arguments", "operand-extra", "command",
    ));
    assert!(!case.state.exists(), "a refused events writes nothing");
}

/// `telemetry show` before any answer, after every kind of event was
/// produced, and with a queued event file that is damaged or unreadable.
#[test]
fn telemetry_show_prints_the_queue_each_event_as_declared() {
    let mut case = Case::new("show");

    // Unanswered: a reported failure queues nothing and keeps nothing.
    case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found"]).succeeded();
    assert_eq!(case.run(&["telemetry", "show"]).succeeded(), json!([]));
    assert!(!case.state.exists(), "nothing is kept before the user answers: {}", case.state.display());

    // Every kind, under usage: a failure and its repeat, a command refused
    // as usage twice and its loop, and help asked after the failure.
    case.run(&["telemetry", "level", "usage"]).succeeded();
    for _ in 0..2 {
        case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found", "--cause-id", "pairs-unreadable"]).succeeded();
        case.run(&["telemetry", "command", "pairs import", "2", "3"]).succeeded();
    }
    case.run(&["telemetry", "help", "pairs import"]).succeeded();
    let queued = case.queued();
    let shown = case.run(&["telemetry", "show"]).succeeded();
    assert_eq!(shown, Value::Array(queued.clone()), "show prints the queue on disk, oldest first");

    let declared = case.bare(&["telemetry", "events"]).succeeded();
    let mut seen = BTreeSet::new();
    for event in &queued {
        let name = event["eventName"].as_str().expect("an event name");
        let Some(declaration) = declared.as_array().expect("the declared events").iter().find(|declaration| declaration["name"] == name) else {
            panic!("{name} is queued and `telemetry events` does not list it");
        };
        let carried: BTreeSet<&str> = event["properties"].as_object().expect("properties").keys().map(String::as_str).collect();
        let promised: BTreeSet<&str> = declaration["properties"]
            .as_array()
            .expect("its properties")
            .iter()
            .map(|property| property.as_str().expect("a property name"))
            .collect();
        assert_eq!(carried, promised, "{name} carries other properties than it declares");
        assert_eq!((&event["appId"], &event["appVersion"]), (&json!("example-product-cli"), &json!("1.0.0")));
        seen.insert(name);
    }
    let all: BTreeSet<&str> = declared
        .as_array()
        .expect("the declared events")
        .iter()
        .map(|declaration| declaration["name"].as_str().expect("an event name"))
        .collect();
    assert_eq!(seen, all, "every declared event was produced by this case");

    case.run(&["telemetry", "show", "--all"]).refused(USAGE, &refusal(
        "reading the options of `wisent-errors telemetry show`: \"--all\" is not an option the command takes; observed: its options are none",
        "drop \"--all\", or write in its place an option the command takes, as in `wisent-errors --product <file> telemetry show`",
        "wisent_errors.command.arguments", "option-unknown", "command",
    ));

    // A queued event cut short, as a crash mid-write of another program leaves it.
    let damaged = case.state.join("queue").join("00000000-0000-4000-8000-000000000000.json");
    std::fs::write(&damaged, "{").expect("the damaged event");
    let decoder = serde_json::from_str::<Value>("{").expect_err("not JSON").to_string();
    let path = damaged.display().to_string();
    case.run(&["telemetry", "show"]).refused(FAILURE, &[
        format!("Error: reading a queued event from {path}: the file is not an event telemetry queued: {decoder}; observed: the file holds 1 bytes"),
        format!("fix: remove {path}: the event it held is lost, as nothing in {PRODUCT} queues it again, and the events beside it are sent as they were"),
        cause("wisent-errors.telemetry.store", "queued-event-unreadable", "telemetry"),
    ]);
    assert_eq!(std::fs::read_to_string(&damaged).expect("the damaged event"), "{", "show leaves it as it was");

    // The same file, readable to no one:
    // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    std::fs::set_permissions(&damaged, std::fs::Permissions::from_mode(0o000)).expect("its permissions can be withdrawn");
    let denied = std::fs::read(&damaged).expect_err("the file is refused to this user").to_string();
    let ran = case.run(&["telemetry", "show"]);
    // Owner read and write, given back so the case can be removed.
    std::fs::set_permissions(&damaged, std::fs::Permissions::from_mode(0o600)).expect("its permissions can be given back");
    ran.refused(FAILURE, &[
        format!("Error: reading a queued event from {path}: the operating system refused the read, so the event it holds was never looked at; observed: {path} is a file of 1 bytes; the operating system answered {denied}"),
        format!("fix: let the user running {PRODUCT} read it (chmod u+r {path}) so the event is sent; or remove {path}, and the event it held is lost, as nothing in {PRODUCT} queues it again"),
        cause("wisent-errors.telemetry.store", "queued-event-read-refused", "telemetry"),
    ]);
    assert_eq!(std::fs::read_to_string(&damaged).expect("the damaged event"), "{");
}
