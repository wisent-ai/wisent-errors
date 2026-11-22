//! `telemetry flush` against the real Echo app collector: an accepted event
//! leaves the queue, an app it does not declare stays queued with its
//! refusal, a collector failing on its own side keeps the events with its
//! own failure, and an address that answers but is not the collector is
//! named.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry delivery::reached::
//!
//! - Rule 4: the flush is the crate's command line run as a process
//!   (`Case::run`, main.rs), its event queued by the command's own
//!   `telemetry failure`, sent over the network to the real collector
//!   `WISENT_TELEMETRY_TEST_COLLECTOR` names (with the app its deployment
//!   declares, `WISENT_TELEMETRY_TEST_APP_ID`, and a deployment failing on
//!   its own side, `WISENT_TELEMETRY_TEST_FAILING_COLLECTOR`), given to the
//!   command as its own `WISENT_TELEMETRY_COLLECTOR_URL`. That variable is
//!   not a stand-in: it is how an operator points the product at a
//!   self-hosted Echo, and the collector at the other end is the real one.
//!   A case whose variable is unset fails with `blocked:` naming it.
//! - Rule 5: each case reads back the exit status, the document the flush
//!   printed, the whole refusal on stderr, `delivery.json` and the queue on
//!   disk: an accepted event is gone from the queue directory, a refused
//!   one is still there, byte for byte the event that was queued.
//!
//! What the collector says in its own words is the one part of a sentence
//! read only as part (and, for its declared refusal, parsed and compared
//! field by field); the rest of each sentence is compared whole.

use serde_json::{json, Value};

use super::{delivery, queue_one, queued_event, stopped, DECLARED_APP, ONE_WAITS};
use crate::{cause, collector, elsewhere, Case, FAILURE, PRODUCT, RETRY};

#[test]
fn an_event_reaches_the_collector() {
    let mut case = Case::for_app("accepted", &DECLARED_APP);
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", collector());
    let event = queue_one(&mut case);
    let sent = case.run(&["telemetry", "flush"]).succeeded();
    case.note("event", json!(event));
    assert_eq!(sent, json!({ "sent": 1, "remaining": 0, "stopped": null, "skipped": null }));
    assert!(case.queued().is_empty(), "the accepted event left the queue");
    assert_eq!((&delivery(&case)["sent"], &delivery(&case)["remaining"]), (&json!(1), &json!(0)));
    assert_eq!(case.run(&["telemetry", "status"]).succeeded()["queued"], 0);
}

#[test]
fn an_app_the_collector_does_not_declare_stays_queued_with_its_refusal() {
    let app = "example-product-undeclared";
    let mut case = Case::for_app("undeclared-app", app);
    let address = collector();
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", address.as_str());
    let event = queue_one(&mut case);
    let queued = case.queued();
    let ran = case.run(&["telemetry", "flush"]);
    // The collector's own answer, HTTP 403 (https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.4).
    let answer = stopped(
        &case,
        &ran,
        FAILURE,
        &format!("sending event {event} to {address}: the collector refused HTTP 403: "),
        ONE_WAITS,
        &[
            format!("fix: the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app {app} in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush"),
            cause("wisent-errors.telemetry.deliver", "collector-refused", "telemetry"),
        ],
    );
    // Echo's declared refusal (echo-web src/lib/failure/declared/operations/integrations/collect.ts, app-undeclared).
    let answer: Value = serde_json::from_str(&answer).expect("the collector answers JSON");
    let Some((_, path)) = address.split_once("://").and_then(|(_, rest)| rest.find('/').map(|at| rest.split_at(at))) else {
        panic!("the collector address has a path: {address}");
    };
    assert_eq!(
        (&answer["operation"], &answer["cause"], &answer["error"], &answer["remedy"]),
        (
            &json!("echo.analytics.collect"),
            &json!("app-undeclared"),
            &json!(format!("POST {path}: recording an event of mobile app {app}: no mobile app this deployment declares with a collector answers to {app}, so an event from it is not stored; observed: the beacon named app {app}")),
            &json!(format!("send the app id the mobile analytics settings declare, or declare {app} there with its collector URL and an analytics backend")),
        ),
        "the collector's own words"
    );
    assert_eq!(delivery(&case)["stopped"]["error_code"], "refused");
    assert_eq!(case.queued(), queued, "the refused event still waits, as it was queued");
}

/// A collector deployment that answers every event of a declared app with
/// a server error, such as an Echo whose database it cannot reach.
fn failing_collector() -> String {
    match std::env::var("WISENT_TELEMETRY_TEST_FAILING_COLLECTOR") {
        Ok(address) => address,
        Err(error) => panic!(
            "blocked: WISENT_TELEMETRY_TEST_FAILING_COLLECTOR is not set ({error}); set it to a collector deployment that answers with a server error, such as an Echo that cannot reach its database"
        ),
    }
}

#[test]
fn a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure() {
    let failing = failing_collector();
    // The collector checks the app before it writes: only an app it declares
    // reaches the store that fails.
    let mut case = Case::for_app("failing-collector", &DECLARED_APP);
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", failing.as_str());
    let event = queue_one(&mut case);
    let queued = case.queued();
    let ran = case.run(&["telemetry", "flush"]);
    // The 5xx server error class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
    let answer = stopped(
        &case,
        &ran,
        RETRY,
        &format!("sending event {event} to {failing}: the collector failed on its own side, HTTP 5"),
        ONE_WAITS,
        &[
            format!("fix: nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `{PRODUCT} support report`, or from an app's Help → Report a Problem"),
            cause("wisent-errors.telemetry.deliver", "collector-failed", "telemetry"),
        ],
    );
    assert!(answer.len() > 4, "the status and the collector's own words follow HTTP 5: {answer}");
    assert_eq!(delivery(&case)["stopped"]["error_code"], "infra_down");
    assert_eq!(case.queued(), queued, "the event still waits");
}

#[test]
fn an_address_that_is_not_a_collector_is_named() {
    let mut case = Case::new("not-a-collector");
    let address = elsewhere("/robots.txt");
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", address.as_str());
    let event = queue_one(&mut case);
    let ran = case.run(&["telemetry", "flush"]);
    let rest = stopped(
        &case,
        &ran,
        RETRY,
        &format!("reading the collector's answer to event {event}: the answer is not the collector's {{\"ok\": true}}: "),
        &format!(" from {address}"),
        &[
            format!("fix: check that {address} is the Echo app collector, /api/analytics/mobile/collect"),
            cause("wisent-errors.telemetry.deliver", "collector-answer-unreadable", "telemetry"),
        ],
    );
    let Some((_, status)) = rest.rsplit_once("; observed: HTTP ") else {
        panic!("the refusal names the HTTP status: {rest}");
    };
    assert!(status.parse::<u16>().is_ok(), "an HTTP status: {rest}");
    assert_eq!(queued_event(&case), event, "the event still waits");
}
