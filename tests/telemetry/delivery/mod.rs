//! Delivery: what the real Echo app collector accepts leaves the queue, every
//! way it can stop is named with its whole sentence and leaves the events
//! waiting on disk, and an address or a flush that cannot be used is refused
//! before anything is sent. `reached` holds the cases that talk to the real
//! collector, `unreached` those that never reach one.

mod reached;
mod unreached;

use std::sync::LazyLock;

use serde_json::Value;
use wisent_errors::telemetry::Telemetry;

use crate::Case;

/// `delivery.json`, the outcome of the last flush as `telemetry status` reads it.
fn delivery(case: &Case) -> Value {
    let text = std::fs::read_to_string(case.root.join("state").join("delivery.json"))
        .expect("the delivery record");
    serde_json::from_str(&text).expect("JSON")
}

/// The id of the one event waiting in `telemetry`'s queue.
fn queued_event(telemetry: &Telemetry) -> String {
    let queued = telemetry.queued().expect("the queue reads");
    let [event] = queued.as_slice() else {
        panic!("one event is queued: {queued:?}");
    };
    event["eventId"].as_str().expect("the event's id").to_owned()
}

/// The app the collector's MOBILE_ANALYTICS_APPS_JSON declares for these
/// cases, read once.
static DECLARED_APP: LazyLock<String> = LazyLock::new(|| {
    std::env::var("WISENT_TELEMETRY_TEST_APP_ID").expect(
        "set WISENT_TELEMETRY_TEST_APP_ID to an app the collector's MOBILE_ANALYTICS_APPS_JSON declares",
    )
});

/// What a flush that stopped with one event still waiting says it observed.
const ONE_WAITS: &str = "; observed: 1 event(s) stay queued";
