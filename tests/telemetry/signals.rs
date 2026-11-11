//! The frustration signals the reporter counts, through the real store of a
//! case of its own: a repeat is queued with how many times in a row it
//! happened, something else ends the run, and each signal is counted only
//! under the consent it needs.

use std::time::Duration;

use serde_json::Value;
use wisent_errors::telemetry::Level;
use wisent_errors::{Code, Failure};

use crate::{sample_failure, Case};

fn signals(queued: &[Value], name: &str) -> Vec<Value> {
    queued
        .iter()
        .filter(|event| event["eventName"] == name)
        .map(|event| event["properties"].clone())
        .collect()
}

fn other_failure() -> Failure {
    Failure::new(
        "wisent-errors-test.model.load",
        Code::NotFound,
        "wisent-errors-test",
    )
    .expect("a valid failure point")
    .detail("the model is not there")
}

#[test]
fn the_same_failure_again_is_a_repeat_counted_in_a_row() {
    let mut case = Case::new("repeat-failure");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    assert!(signals(
        &telemetry.queued().expect("the queue reads"),
        "frustration.repeat_failure"
    )
    .is_empty());
    telemetry.failure(&sample_failure(), None);
    telemetry.failure(&sample_failure(), None);
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    let repeats = signals(&queued, "frustration.repeat_failure");
    assert_eq!(repeats.len(), 2, "{repeats:?}");
    let counts: Vec<u64> = repeats
        .iter()
        .map(|repeat| repeat["consecutive"].as_u64().expect("a count"))
        .collect();
    assert!(counts.contains(&2) && counts.contains(&3), "{counts:?}");
    assert!(repeats
        .iter()
        .all(|repeat| repeat["failure_point"] == "wisent-errors-test.pairs.import"));
    assert!(repeats
        .iter()
        .all(|repeat| repeat["seconds_since_previous"].is_u64()));

    telemetry.failure(&other_failure(), None);
    telemetry.failure(&sample_failure(), None);
    let after = signals(
        &telemetry.queued().expect("the queue reads"),
        "frustration.repeat_failure",
    );
    assert_eq!(
        after.len(),
        2,
        "another failure in between ends the run: {after:?}"
    );
}

#[test]
fn the_same_usage_refusal_again_is_a_usage_loop_and_success_ends_it() {
    let mut case = Case::new("usage-loop");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Usage)
        .expect("the level is kept");
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    let loops = signals(&queued, "frustration.usage_loop");
    assert_eq!(loops.len(), 1, "{loops:?}");
    assert_eq!(loops[0]["command"], "pairs import");
    assert_eq!(loops[0]["consecutive"], 2);

    telemetry.command("pairs import", 0, Duration::from_millis(3));
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    let after = signals(
        &telemetry.queued().expect("the queue reads"),
        "frustration.usage_loop",
    );
    assert_eq!(
        after.len(),
        1,
        "a command that ran ends the loop: {after:?}"
    );
}

#[test]
fn each_signal_is_counted_only_under_its_consent() {
    let mut case = Case::new("signal-consent");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.failure(&sample_failure(), None);
    telemetry.failure(&sample_failure(), None);
    assert!(
        !case.root.join("state").join("signals.json").exists(),
        "nothing is kept before the user answers"
    );
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    telemetry.command("pairs import", 2, Duration::from_millis(3));
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    assert!(
        signals(&queued, "frustration.usage_loop").is_empty(),
        "commands are not counted under errors"
    );
}

#[test]
fn help_asked_after_a_failure_names_the_failure_and_its_age() {
    let mut case = Case::new("help-after-failure");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Usage)
        .expect("the level is kept");
    telemetry.help("pairs import");
    assert!(
        signals(
            &telemetry.queued().expect("the queue reads"),
            "frustration.help_after_failure"
        )
        .is_empty(),
        "help with no failure before it is no signal"
    );
    telemetry.failure(&sample_failure(), None);
    telemetry.help("pairs import");
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    let helps = signals(&queued, "frustration.help_after_failure");
    assert_eq!(helps.len(), 1, "{helps:?}");
    assert_eq!(helps[0]["command"], "pairs import");
    assert_eq!(helps[0]["failure_point"], "wisent-errors-test.pairs.import");
    assert!(helps[0]["seconds_since_failure"].is_u64());

    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.help("pairs import");
    assert_eq!(
        signals(
            &telemetry.queued().expect("the queue reads"),
            "frustration.help_after_failure"
        )
        .len(),
        1,
        "help is usage, not counted under errors"
    );
}
