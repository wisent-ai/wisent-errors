//! Every event the reporter queues is one `telemetry::EVENTS` declares, and
//! carries exactly the properties it declares: the catalogue a product's
//! privacy page shows is what is sent. Each kind is produced for real in the
//! store of a case of its own.

use std::collections::BTreeSet;
use std::time::Duration;

use serde_json::Value;
use wisent_errors::telemetry::{Level, EVENTS};

use crate::{sample_failure, Case};

#[test]
fn every_queued_event_is_declared_with_exactly_its_properties() {
    let mut case = Case::new("event-catalogue");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Usage)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    telemetry.help("pairs import");
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));

    let mut seen = BTreeSet::new();
    for event in &queued {
        let name = event["eventName"].as_str().expect("an event name");
        let declared = EVENTS
            .iter()
            .find(|declared| declared.name == name)
            .unwrap_or_else(|| panic!("{name} is queued and not declared in telemetry::EVENTS"));
        let carried: BTreeSet<&str> = event["properties"]
            .as_object()
            .expect("properties")
            .keys()
            .map(String::as_str)
            .collect();
        let promised: BTreeSet<&str> = declared.properties.iter().copied().collect();
        assert_eq!(
            carried, promised,
            "{name} carries other properties than it declares"
        );
        seen.insert(name);
    }
    let all: BTreeSet<&str> = EVENTS.iter().map(|declared| declared.name).collect();
    assert_eq!(seen, all, "every declared event was produced by this case");
}
