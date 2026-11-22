//! `telemetry flush` where no collector is reached: before consent and
//! under DO_NOT_TRACK nothing is tried, nothing listening keeps the events,
//! the last delivery is dated in local time, a plain-http address is
//! refused by name, the public collector is named when none is set, and a
//! background flush the product file names that cannot start is said.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry delivery::unreached::
//!
//! Each case runs the crate's command line as a process (`Case::run`,
//! main.rs) and reads back the exit status, the printed document, the whole
//! refusal, `delivery.json` and the queue on disk. What the transport and
//! the operating system say is read by asking them the same way, or as the
//! one part of a sentence read only as part; the rest is each cause's
//! catalogue template rendered whole with the values the case observes.

use std::process::{Command, Stdio};

use serde_json::{json, Value};

use super::{delivery, queue_one, stopped, ONE_WAITS};
use crate::{cause, refusal, Case, FAILURE, NOTHING_LISTENS, PRODUCT, RETRY, SUCCESS};

/// The collector's path on the discard port, where nothing listens.
fn nothing_listens() -> String {
    format!("{NOTHING_LISTENS}/api/analytics/mobile/collect")
}

#[test]
fn an_unreachable_collector_keeps_the_events() {
    let mut case = Case::new("unreachable");
    let address = nothing_listens();
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", address.as_str());

    // Unanswered, nothing is queued, so nothing is tried.
    let skipped = case.run(&["telemetry", "flush"]).succeeded();
    assert_eq!(skipped, json!({ "sent": 0, "remaining": 0, "stopped": null, "skipped": "unanswered" }));
    assert!(!case.state.exists(), "a skipped flush keeps nothing");

    let event = queue_one(&mut case);
    case.set("DO_NOT_TRACK", "1");
    let skipped = case.run(&["telemetry", "flush"]).succeeded();
    assert_eq!(skipped, json!({ "sent": 0, "remaining": 1, "stopped": null, "skipped": "DO_NOT_TRACK" }));
    assert!(!case.holds("delivery.json"), "a skipped flush tries nothing and records nothing");
    case.unset("DO_NOT_TRACK");

    let queued = case.queued();
    let ran = case.run(&["telemetry", "flush"]);
    let why = stopped(
        &case,
        &ran,
        RETRY,
        &format!("sending event {event} to {address}: the collector could not be reached: "),
        ONE_WAITS,
        &[
            "fix: nothing to do: the events are sent on the next flush once the network or the collector is back".to_owned(),
            cause("wisent-errors.telemetry.deliver", "collector-unreachable", "telemetry"),
        ],
    );
    assert!(why.contains("Connection refused"), "the transport's own words: {why}");
    assert_eq!(delivery(&case)["stopped"]["error_code"], "infra_down");
    assert_eq!(case.queued(), queued, "the event still waits, as it was queued");
}

/// `delivery.json` says when the last delivery was tried, which a person
/// reads in `telemetry status`: in this host's local time with its offset,
/// never a bare UTC `Z`. The command is given this process's TZ, when it
/// has one, so both read the same zone.
#[test]
fn the_last_delivery_says_when_in_local_time_with_its_offset() {
    let mut case = Case::new("delivery-moment");
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", nothing_listens());
    queue_one(&mut case);
    let ran = case.run(&["telemetry", "flush"]);
    assert_eq!(ran.status, RETRY, "{:?}", ran.said());
    let at = delivery(&case)["at"].as_str().expect("the moment of the delivery").to_owned();
    case.note("at", json!(at));
    assert!(!at.ends_with('Z'), "{at}");
    let moment = chrono::DateTime::parse_from_rfc3339(&at).expect("RFC 3339");
    assert_eq!(
        moment.offset().local_minus_utc(),
        chrono::Local::now().offset().local_minus_utc(),
        "{at} is in this host's offset"
    );
    assert_eq!(case.run(&["telemetry", "status"]).succeeded()["last_delivery"]["at"], json!(at), "status reads the same moment");
}

#[test]
fn a_plain_http_collector_is_refused_by_name() {
    let mut case = Case::new("plain-http");
    let address = "http://collector.example.invalid/api/analytics/mobile/collect";
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", address);
    queue_one(&mut case);
    let queued = case.queued();
    let ran = case.run(&["telemetry", "flush"]);
    let sentence = format!("reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds {address}");
    stopped(
        &case,
        &ran,
        FAILURE,
        &sentence,
        "",
        &refusal(&sentence, "set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it", "wisent-errors.telemetry.deliver", "collector-invalid", "telemetry")[1..],
    );
    assert_eq!(delivery(&case)["stopped"]["error_code"], "config");
    assert_eq!(case.queued(), queued, "nothing was sent");
    assert_eq!(case.run(&["telemetry", "status"]).succeeded()["collector"], Value::Null);
}

#[test]
fn without_an_address_the_public_collector_is_named() {
    let mut case = Case::new("public-collector");
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!(
        (&status["collector"], &status["collector_source"]),
        (&json!("https://telemetry.wisent.com/api/analytics/mobile/collect"), &json!("wisent-errors"))
    );
    let own = "https://collector.example.com/api/analytics/mobile/collect";
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", own);
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!((&status["collector"], &status["collector_source"]), (&json!(own), &json!("WISENT_TELEMETRY_COLLECTOR_URL")));
    assert!(!case.state.exists(), "status sends nothing and keeps nothing");
}

/// A product file whose `flush` names a program that is not there: the
/// failure is queued and printed, the start that failed is said on stderr
/// as telemetry says its own failures, and the command goes on.
#[test]
fn a_flush_that_cannot_start_is_named() {
    let mut case = Case::new("unstarted-flush");
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", nothing_listens());
    case.run(&["telemetry", "level", "errors"]).succeeded();
    let missing = case.root.join("no-such-program");
    let program = missing.display().to_string();
    std::fs::write(
        &case.product,
        json!({ "id": PRODUCT, "app_id": "example-product-cli", "version": "1.0.0", "flush": [program, "telemetry", "flush"] }).to_string(),
    )
    .expect("the product file");
    let why = Command::new(&missing).stdin(Stdio::null()).spawn().expect_err("nothing is at the path").to_string();
    let status = case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found"]).ended(
        SUCCESS,
        &[format!(
            "wisent-errors: telemetry: starting {program} to send the queued events: the process could not be started: {why}{ONE_WAITS}; fix: run `{PRODUCT} telemetry flush` yourself; the events wait until it runs"
        )],
    );
    assert_eq!(status["queued"], 1);
    assert_eq!(case.queued().len(), 1, "the event waits for the next flush");
    assert!(!missing.exists() && !case.holds("delivery.json"), "nothing was started and nothing tried to send");
}
