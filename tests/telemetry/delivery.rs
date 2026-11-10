//! Delivery against the real Echo app collector: what it accepts leaves the
//! queue, and every way it can stop is named and leaves the events waiting.

use std::net::TcpListener;
use std::sync::LazyLock;

use serde_json::{json, Value};
use wisent_errors::telemetry::{Level, PUBLIC_COLLECTOR};

use crate::{collector, sample_failure, Case};

fn delivery(case: &Case) -> Value {
    let text = std::fs::read_to_string(case.root.join("state").join("delivery.json"))
        .expect("the delivery record");
    serde_json::from_str(&text).expect("JSON")
}

/// The app the collector's MOBILE_ANALYTICS_APPS_JSON declares for these
/// cases, read once.
static DECLARED_APP: LazyLock<String> = LazyLock::new(|| {
    std::env::var("WISENT_TELEMETRY_TEST_APP_ID").expect(
        "set WISENT_TELEMETRY_TEST_APP_ID to an app the collector's MOBILE_ANALYTICS_APPS_JSON declares",
    )
});

#[test]
fn an_event_reaches_the_collector() {
    let mut case = Case::new("accepted");
    let app: &'static str = DECLARED_APP.as_str();
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", collector());
    let telemetry = case.telemetry(app);
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    let event_id = telemetry.queued().expect("the queue reads")[0]["eventId"].clone();
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("event", event_id);
    case.note("delivered", delivered.to_json());
    assert!(delivered.stopped.is_none(), "{:?}", delivered.stopped);
    assert_eq!((delivered.sent, delivered.remaining), (1, 0));
    assert_eq!(telemetry.status()["queued"], 0);
}

#[test]
fn an_app_the_collector_does_not_declare_stays_queued_with_its_refusal() {
    let mut case = Case::new("undeclared-app");
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", collector());
    let telemetry = case.telemetry("wisent-errors-test-undeclared");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    let stopped = delivered.stopped.expect("the refusal");
    assert_eq!(stopped.code.as_str(), "refused");
    let detail = stopped.detail.expect("a sentence");
    assert!(detail.contains("HTTP 403"), "{detail}");
    assert!(
        detail.contains("Unknown mobile analytics app"),
        "the collector's own words: {detail}"
    );
    assert!(stopped
        .remedy
        .expect("a fix")
        .contains("wisent-errors-test-undeclared"));
    assert_eq!(delivery(&case)["stopped"]["error_code"], "refused");
    assert_eq!(telemetry.status()["queued"], 1);
}

#[test]
fn an_unreachable_collector_keeps_the_events() {
    let mut case = Case::new("unreachable");
    let port = TcpListener::bind("127.0.0.1:0")
        .expect("a free port")
        .local_addr()
        .expect("its address")
        .port();
    std::env::set_var(
        "WISENT_TELEMETRY_COLLECTOR_URL",
        format!("http://127.0.0.1:{port}/api/analytics/mobile/collect"),
    );
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    let stopped = delivered.stopped.expect("the transport error");
    assert_eq!(stopped.code.as_str(), "infra_down");
    assert!(stopped.retryable());
    assert!(stopped
        .detail
        .expect("a sentence")
        .contains(&format!("127.0.0.1:{port}")));
}

#[test]
fn an_address_that_is_not_a_collector_is_named() {
    let mut case = Case::new("not-a-collector");
    let real = collector();
    let origin_end = real
        .find("/api/")
        .expect("the collector address has the /api/ path");
    let elsewhere = format!("{}/robots.txt", &real[..origin_end]);
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", &elsewhere);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!(delivered.remaining, 1);
    let stopped = delivered.stopped.expect("the unreadable answer");
    let remedy = stopped.remedy.expect("a fix");
    assert!(remedy.contains(&elsewhere), "{remedy}");
    assert!(remedy.contains("/api/analytics/mobile/collect"), "{remedy}");
}

#[test]
fn a_plain_http_collector_is_refused_by_name() {
    let mut case = Case::new("plain-http");
    std::env::set_var(
        "WISENT_TELEMETRY_COLLECTOR_URL",
        "http://collector.example/api/analytics/mobile/collect",
    );
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .collector()
        .expect_err("plain http to another host is refused");
    case.note("refusal", json!(refused.detail));
    let detail = refused.detail.expect("a sentence");
    assert!(
        detail.contains("WISENT_TELEMETRY_COLLECTOR_URL"),
        "{detail}"
    );
    assert!(detail.contains("http://collector.example"), "{detail}");
    assert_eq!(telemetry.status()["collector"], Value::Null);
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
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", collector());
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let missing = case.root.join("no-such-program");
    let refused = telemetry
        .spawn_flush(&missing, &["telemetry", "flush"])
        .expect("the start fails");
    case.note("refusal", json!(refused.detail));
    let detail = refused.detail.expect("a sentence");
    assert!(detail.contains("no-such-program"), "{detail}");
    assert!(refused
        .remedy
        .expect("a fix")
        .contains("wisent-errors-test telemetry flush"));
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
