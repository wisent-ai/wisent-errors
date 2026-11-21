//! Delivery to the real Echo app collector: an accepted event leaves the
//! queue, an app it does not declare stays queued with its refusal, a
//! collector failing on its own side keeps the events with its own failure,
//! and an address that answers but is not the collector is named. What the
//! collector says in its own words is the one part of a sentence read only
//! as part; the rest of each sentence is compared whole.

use wisent_errors::telemetry::Level;

use super::{delivery, queued_event, DECLARED_APP, ONE_WAITS};
use crate::{collector, sample_failure, Case};

/// The middle of `detail` between the exact `prefix` and `suffix`, which it must hold.
fn between<'a>(detail: &'a str, prefix: &str, suffix: &str) -> &'a str {
    detail
        .strip_prefix(prefix)
        .and_then(|rest| rest.strip_suffix(suffix))
        .unwrap_or_else(|| panic!("{detail:?} is not {prefix:?}…{suffix:?}"))
}

#[test]
fn an_event_reaches_the_collector() {
    let mut case = Case::new("accepted");
    let app: &'static str = DECLARED_APP.as_str();
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", collector());
    let telemetry = case.telemetry(app);
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    let event_id = queued_event(&telemetry);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("event", serde_json::json!(event_id));
    case.note("delivered", delivered.to_json());
    assert!(delivered.stopped.is_none(), "{:?}", delivered.stopped);
    assert_eq!((delivered.sent, delivered.remaining), (1, 0));
    assert_eq!(telemetry.queued().expect("the queue reads"), Vec::<serde_json::Value>::new());
    assert_eq!(telemetry.status()["queued"], 0);
    assert_eq!(delivery(&case)["sent"], 1);
}

#[test]
fn an_app_the_collector_does_not_declare_stays_queued_with_its_refusal() {
    let mut case = Case::new("undeclared-app");
    let address = collector();
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", &address);
    let telemetry = case.telemetry("wisent-errors-test-undeclared");
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let event = queued_event(&telemetry);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    let stopped = delivered.stopped.expect("the refusal");
    assert_eq!(stopped.code.as_str(), "refused");
    let detail = stopped.detail.expect("a sentence");
    // The collector's own answer, HTTP 403 (https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.4).
    let answer = between(&detail, &format!("sending event {event} to {address}: the collector refused HTTP 403: "), ONE_WAITS);
    // Echo's declared refusal (echo-web src/lib/failure/declared/operations/integrations/collect.ts, app-undeclared).
    let answer: serde_json::Value = serde_json::from_str(answer).expect("the collector answers JSON");
    let path = address.split_once("://").and_then(|(_, rest)| rest.find('/').map(|at| &rest[at..])).expect("the collector address has a path");
    let app = "wisent-errors-test-undeclared";
    assert_eq!(
        (answer["operation"].as_str(), answer["cause"].as_str(), answer["error"].as_str(), answer["remedy"].as_str()),
        (
            Some("echo.analytics.collect"),
            Some("app-undeclared"),
            Some(format!("POST {path}: recording an event of mobile app {app}: no mobile app this deployment declares with a collector answers to {app}, so an event from it is not stored; observed: the beacon named app {app}").as_str()),
            Some(format!("send the app id the mobile analytics settings declare, or declare {app} there with its collector URL and an analytics backend").as_str()),
        ),
        "the collector's own words"
    );
    assert_eq!(
        stopped.remedy.as_deref(),
        Some("the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app wisent-errors-test-undeclared in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush")
    );
    let kept = delivery(&case);
    assert_eq!((kept["stopped"]["error_code"].as_str(), kept["stopped"]["detail"].as_str()), (Some("refused"), Some(detail.as_str())));
    assert_eq!(queued_event(&telemetry), event, "the refused event still waits");
}

/// A collector deployment that answers every event of a declared app with a
/// server error, such as an Echo whose database it cannot reach, read once.
static FAILING_COLLECTOR: std::sync::LazyLock<String> = std::sync::LazyLock::new(|| {
    std::env::var("WISENT_TELEMETRY_TEST_FAILING_COLLECTOR").expect(
        "set WISENT_TELEMETRY_TEST_FAILING_COLLECTOR to a collector deployment that answers with a server error, such as an Echo that cannot reach its database",
    )
});

#[test]
fn a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure() {
    let mut case = Case::new("failing-collector");
    let failing = FAILING_COLLECTOR.as_str();
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", failing);
    // The collector checks the app before it writes: only an app it declares
    // reaches the store that fails.
    let telemetry = case.telemetry(DECLARED_APP.as_str());
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let event = queued_event(&telemetry);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    let stopped = delivered.stopped.expect("the collector's failure");
    assert_eq!(stopped.code.as_str(), "infra_down");
    let detail = stopped.detail.expect("a sentence");
    // The 5xx server error class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
    let answer = between(&detail, &format!("sending event {event} to {failing}: the collector failed on its own side, HTTP 5"), ONE_WAITS);
    assert!(!answer.is_empty(), "{detail}");
    assert_eq!(
        stopped.remedy.as_deref(),
        Some("nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `wisent-errors-test support report`, or from an app's Help → Report a Problem")
    );
    assert_eq!(delivery(&case)["stopped"]["error_code"], "infra_down");
    assert_eq!(queued_event(&telemetry), event, "the event still waits");
}

#[test]
fn an_address_that_is_not_a_collector_is_named() {
    let mut case = Case::new("not-a-collector");
    let real = collector();
    let origin_end = real.find("/api/").expect("the collector address has the /api/ path");
    let elsewhere = format!("{}/robots.txt", &real[..origin_end]);
    std::env::set_var("WISENT_TELEMETRY_COLLECTOR_URL", &elsewhere);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.set_level(Level::Errors).expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    let event = queued_event(&telemetry);
    let delivered = telemetry.flush().expect("the store is readable");
    case.note("delivered", delivered.to_json());
    assert_eq!((delivered.sent, delivered.remaining), (0, 1));
    let stopped = delivered.stopped.expect("the unreadable answer");
    assert_eq!(stopped.code.as_str(), "infra_down");
    let detail = stopped.detail.expect("a sentence");
    let rest = detail
        .strip_prefix(&format!("reading the collector's answer to event {event}: the answer is not the collector's {{\"ok\": true}}: "))
        .unwrap_or_else(|| panic!("{detail}"));
    let (_, status) = rest.rsplit_once("; observed: HTTP ").unwrap_or_else(|| panic!("{detail}"));
    let status = status.strip_suffix(&format!(" from {elsewhere}")).unwrap_or_else(|| panic!("{detail}"));
    assert!(status.parse::<u16>().is_ok(), "an HTTP status: {detail}");
    assert_eq!(
        stopped.remedy.as_deref(),
        Some(format!("check that {elsewhere} is the Echo app collector, /api/analytics/mobile/collect").as_str())
    );
    assert_eq!(queued_event(&telemetry), event, "the event still waits");
}
