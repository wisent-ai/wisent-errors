//! Delivery that never reaches a collector: nothing listening keeps the
//! events, a peer that closes without answering ends the flush, the last
//! delivery is dated in local time, a plain-http address is refused by name,
//! the public collector is named when none is set, and a flush that cannot
//! start is named. Each refusal is compared whole; what the transport and
//! the operating system say is read by asking them the same way, or as the
//! one part of a sentence read only as part.

use std::process::{Command, Stdio};

use serde_json::{json, Value};
use wisent_errors::telemetry::{Level, PUBLIC_COLLECTOR};

use super::{delivery, queued_event, ONE_WAITS};
use crate::{collector, sample_failure, Case};

/// The discard port on loopback, where nothing listens on a host that runs
/// no discard service: https://www.rfc-editor.org/rfc/rfc863
const NOTHING_LISTENS: &str = "http://127.0.0.1:9/api/analytics/mobile/collect";

const UNREACHABLE_REMEDY: &str = "nothing to do: the events are sent on the next flush once the network or the collector is back";

/// What a flush that could not reach `address` with `event` waiting says,
/// whole but for the transport's own words, which it returns.
fn unreachable(detail: &str, event: &str, address: &str) -> String {
    detail
        .strip_prefix(&format!("sending event {event} to {address}: the collector could not be reached: "))
        .and_then(|rest| rest.strip_suffix(ONE_WAITS))
        .unwrap_or_else(|| panic!("{detail}"))
        .to_owned()
}

#[test]
fn an_unreachable_collector_keeps_the_events() {
    let mut case = Case::new("unreachable");
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", NOTHING_LISTENS);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let event = queued_event(&telemetry);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    let stopped = delivered.stopped.expect("the transport error");
    assert_eq!(stopped.code.as_str(), "infra_down");
    assert!(stopped.retryable());
    let why = unreachable(stopped.detail.as_deref().expect("a sentence"), &event, NOTHING_LISTENS);
    assert!(why.contains("Connection refused"), "the transport's own words: {why}");
    assert_eq!(stopped.remedy.as_deref(), Some(UNREACHABLE_REMEDY));
    assert_eq!(delivery(&case)["stopped"]["detail"], json!(stopped.detail));
    assert_eq!(queued_event(&telemetry), event, "the event still waits");
}

/// `delivery.json` says when the last delivery was tried, which a person
/// reads in `telemetry status`: in this host's local time with its offset,
/// never a bare UTC `Z`.
#[test]
fn the_last_delivery_says_when_in_local_time_with_its_offset() {
    let mut case = Case::new("delivery-moment");
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", NOTHING_LISTENS);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    telemetry.flush().expect("the store is readable");
    let at = delivery(&case)["at"].as_str().expect("the moment of the delivery").to_owned();
    case.note("at", json!(at));
    assert!(!at.ends_with('Z'), "{at}");
    let moment = chrono::DateTime::parse_from_rfc3339(&at).expect("RFC 3339");
    assert_eq!(
        moment.offset().local_minus_utc(),
        chrono::Local::now().offset().local_minus_utc(),
        "{at} is in this host's offset"
    );
}

#[test]
fn a_plain_http_collector_is_refused_by_name() {
    let mut case = Case::new("plain-http");
    let address = "http://collector.example.invalid/api/analytics/mobile/collect";
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", address);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let refused = telemetry.collector().expect_err("plain http to another host is refused");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "config");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!("reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds {address}").as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some("set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it")
    );
    assert_eq!(telemetry.status()["collector"], Value::Null);
    // A flush to the refused address sends nothing and keeps the refusal.
    let delivered = telemetry.flush().expect("the store is readable");
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    assert_eq!(delivery(&case)["stopped"]["detail"], json!(refused.detail));
}

#[test]
fn without_an_address_the_public_collector_is_named() {
    let mut case = Case::new("public-collector");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let status = telemetry.status();
    case.note("status", status.clone());
    assert_eq!(status["collector"], PUBLIC_COLLECTOR);
    assert_eq!(status["collector_source"], "wisent-errors");
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", collector());
    assert_eq!(telemetry.status()["collector"], collector().as_str());
}

#[test]
fn a_flush_that_cannot_start_is_named() {
    let mut case = Case::new("unstarted-flush");
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", NOTHING_LISTENS);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let missing = case.root.join("no-such-program");
    let why = Command::new(&missing)
        .stdin(Stdio::null())
        .spawn()
        .expect_err("nothing is at the path")
        .to_string();
    let refused = telemetry.spawn_flush(&missing, &["telemetry", "flush"]).expect("the start fails");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "config");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!("starting {} to send the queued events: the process could not be started: {why}{ONE_WAITS}", missing.display()).as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some("run `wisent-errors-test telemetry flush` yourself; the events wait until it runs")
    );
    assert_eq!(telemetry.status()["queued"], 1);
}

#[test]
fn every_declared_cause_has_its_test_here() {
    let mut problems = Vec::new();
    for operation in wisent_errors::telemetry::operations() {
        problems.extend(operation.problems());
    }
    let catalogue: Vec<_> = wisent_errors::telemetry::operations().to_vec();
    problems.extend(wisent_errors::catalogue_problems(&catalogue));
    assert!(problems.is_empty(), "{problems:?}");
}
