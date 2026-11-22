//! `wisent-errors --product <file> telemetry flush`: what the real Echo app
//! collector accepts leaves the queue, every way a flush can stop is said
//! whole and leaves the events waiting on disk, and an address or a
//! background flush that cannot be used is refused before anything is
//! sent. `reached` holds the cases that talk to the real collector,
//! `unreached` those that never reach one: a gate host without the
//! collector still runs every case that does not need it.
//!
//! A flush prints what it did (`sent`, `remaining`, `stopped`, `skipped`)
//! and, when it stopped, says why on stderr in the three lines of every
//! refusal and exits with the cause's status; each case reads both, then
//! `delivery.json` and the queue back from disk.

mod reached;
mod unreached;

use std::sync::LazyLock;

use serde_json::{json, Value};

use crate::{between, Case, Ran};

/// `delivery.json`, the outcome of the last flush as `telemetry status` reads it.
fn delivery(case: &Case) -> Value {
    case.json("delivery.json")
}

/// The id of the one event waiting in the case's queue, read from disk.
fn queued_event(case: &Case) -> String {
    let queued = case.queued();
    let [event] = queued.as_slice() else {
        panic!("one event is queued: {queued:?}");
    };
    event["eventId"].as_str().expect("the event's id").to_owned()
}

/// Answer errors and report one failure through the command; the id of
/// the event it queued.
fn queue_one(case: &mut Case) -> String {
    case.run(&["telemetry", "level", "errors"]).succeeded();
    case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found", "--detail", "the pairs file is not there"]).succeeded();
    queued_event(case)
}

/// The app the collector's MOBILE_ANALYTICS_APPS_JSON declares for these
/// cases, read once.
static DECLARED_APP: LazyLock<String> = LazyLock::new(|| match std::env::var("WISENT_TELEMETRY_TEST_APP_ID") {
    Ok(app) => app,
    Err(error) => panic!("blocked: WISENT_TELEMETRY_TEST_APP_ID is not set ({error}); set it to an app the collector's MOBILE_ANALYTICS_APPS_JSON declares"),
});

/// What a flush that stopped with one event still waiting says it observed.
const ONE_WAITS: &str = "; observed: 1 event(s) stay queued";

/// A flush that stopped with the one event it was given still queued: it
/// printed so, exited with `status` and said a refusal whose first line is
/// `prefix`, the words of the collector or the transport, then
/// `suffix`, followed by exactly `rest`. The middle part, which it
/// returns, is read only as part; `delivery.json` keeps the same refusal.
fn stopped(case: &Case, ran: &Ran, status: i32, prefix: &str, suffix: &str, rest: &[String]) -> String {
    let said = ran.said();
    assert_eq!((ran.status, said.len()), (status, rest.len() + 1), "{said:?}");
    assert_eq!(&said[1..], rest, "{said:?}");
    let detail = between(&said[0], "Error: ", "");
    let middle = between(detail, prefix, suffix).to_owned();
    let remedy = rest[0].strip_prefix("fix: ").expect("the fix line");
    let printed = ran.json();
    assert_eq!((&printed["sent"], &printed["remaining"], &printed["skipped"]), (&json!(0), &json!(1), &Value::Null), "{printed}");
    assert_eq!((&printed["stopped"]["detail"], &printed["stopped"]["remedy"]), (&json!(detail), &json!(remedy)), "{printed}");
    let kept = delivery(case);
    assert_eq!(kept["stopped"], printed["stopped"], "delivery.json keeps the refusal");
    middle
}
