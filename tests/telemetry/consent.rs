//! What the user agreed to decides what is queued, and nothing else does.

use std::time::Duration;

use serde_json::{json, Value};
use wisent_errors::telemetry::Level;

use crate::{sample_failure, Case};

#[test]
fn nothing_is_queued_before_the_user_answers() {
    let mut case = Case::new("unanswered");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    telemetry.command("pairs import", 1, Duration::from_millis(5));
    let status = telemetry.status();
    case.note("status", status.clone());
    assert_eq!(status["level"], "unanswered");
    assert_eq!(status["queued"], 0);
    assert!(
        !case.root.join("state").join("installation.json").exists(),
        "no id is made before consent"
    );
}

#[test]
fn errors_queue_failures_and_not_commands() {
    let mut case = Case::new("errors-level");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    telemetry.command("pairs import", 1, Duration::from_millis(5));
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    assert_eq!(queued.len(), 1);
    let event = &queued[0];
    assert_eq!(event["eventName"], "failure");
    assert_eq!(event["appId"], "wisent-errors-test-cli");
    assert_eq!(
        event["properties"]["failure_point"],
        "wisent-errors-test.pairs.import"
    );
    assert_eq!(event["properties"]["error_code"], "not_found");
    assert_eq!(event["properties"]["cause_id"], "pairs-unreadable");
    let home = std::env::var("HOME").expect("HOME");
    let detail = event["properties"]["detail"].as_str().expect("a detail");
    assert!(
        !detail.contains(&home),
        "the home directory is taken out: {detail}"
    );
    assert!(detail.contains("~/pairs/calm.json"), "{detail}");
}

#[test]
fn usage_queues_commands_without_their_arguments() {
    let mut case = Case::new("usage-level");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Usage)
        .expect("the level is kept");
    telemetry.command("pairs import", 0, Duration::from_millis(42));
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    assert_eq!(queued.len(), 1);
    assert_eq!(queued[0]["eventName"], "cli.command");
    assert_eq!(
        queued[0]["properties"],
        json!({ "command": "pairs import", "exit_status": 0, "duration_ms": 42 })
    );
}

#[test]
fn do_not_track_turns_every_level_off() {
    let mut case = Case::new("do-not-track");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Usage)
        .expect("the level is kept");
    std::env::set_var("DO_NOT_TRACK", "1");
    telemetry.failure(&sample_failure(), None);
    let status = telemetry.status();
    std::env::remove_var("DO_NOT_TRACK");
    case.note("status", status.clone());
    assert_eq!(status["do_not_track"], true);
    assert_eq!(status["queued"], 0);
}

#[test]
fn turning_off_drops_what_was_waiting() {
    let mut case = Case::new("turned-off");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    assert_eq!(telemetry.queued().expect("the queue reads").len(), 1);
    telemetry.set_level(Level::Off).expect("the level is kept");
    let status = telemetry.status();
    case.note("status", status.clone());
    assert_eq!(status["level"], "off");
    assert_eq!(status["queued"], 0);
}

#[test]
fn an_unknown_level_is_refused() {
    let mut case = Case::new("unknown-level");
    let refused =
        Level::parse("everything", "wisent-errors-test").expect_err("an unknown level is refused");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "refused");
    let detail = refused.detail.expect("a sentence");
    assert!(detail.contains("got everything"), "{detail}");
    assert_eq!(
        refused.remedy.as_deref(),
        Some("name one of off, errors or usage")
    );
}

#[test]
fn a_damaged_consent_file_is_refused_and_nothing_is_sent() {
    let mut case = Case::new("damaged-consent");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let state = case.root.join("state");
    std::fs::create_dir_all(&state).expect("the state directory");
    std::fs::write(state.join("consent.json"), "{\"level\": \"sometimes\"}")
        .expect("a damaged file");
    let refused = telemetry
        .level()
        .expect_err("a level that is none of the three is refused");
    case.note("refusal", json!(refused.detail));
    let detail = refused.detail.expect("a sentence");
    assert!(detail.contains("consent.json"), "{detail}");
    assert!(detail.contains("sometimes"), "{detail}");
    telemetry.failure(&sample_failure(), None);
    assert_eq!(telemetry.status()["queued"], 0);
}
