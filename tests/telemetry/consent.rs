//! What the user agreed to decides what is queued, and nothing else does.

use std::time::Duration;

use serde_json::{json, Value};
use wisent_errors::telemetry::Level;

use crate::{sample_failure, Case, FAILURE, SUCCESS};

#[test]
fn nothing_is_queued_before_the_user_answers() {
    let mut case = Case::new("unanswered");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    telemetry.command("pairs import", FAILURE, Duration::from_millis(5));
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
    telemetry.command("pairs import", FAILURE, Duration::from_millis(5));
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    let [event] = queued.as_slice() else {
        panic!("one event is queued: {queued:?}");
    };
    assert_eq!(event["eventName"], "failure");
    assert_eq!(event["appId"], "wisent-errors-test-cli");
    assert_eq!(
        event["properties"]["failure_point"],
        "wisent-errors-test.pairs.import"
    );
    assert_eq!(event["properties"]["error_code"], "not_found");
    assert_eq!(event["properties"]["cause_id"], "pairs-unreadable");
    let detail = event["properties"]["detail"].as_str().expect("a detail");
    assert_eq!(
        detail, "reading ~/pairs/calm.json: no such file",
        "the home directory is taken out of what is queued"
    );
}

#[test]
fn usage_queues_commands_without_their_arguments() {
    let mut case = Case::new("usage-level");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Usage)
        .expect("the level is kept");
    telemetry.command("pairs import", SUCCESS, Duration::from_millis(42));
    let queued = telemetry.queued().expect("the queue reads");
    case.note("queued", Value::Array(queued.clone()));
    let [event] = queued.as_slice() else {
        panic!("one event is queued: {queued:?}");
    };
    assert_eq!(event["eventName"], "cli.command");
    assert_eq!(
        event["properties"],
        json!({ "command": "pairs import", "exit_status": SUCCESS, "duration_ms": 42 })
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
    assert_eq!(
        refused.detail.as_deref(),
        Some("setting the telemetry level to everything: telemetry knows the levels off, errors and usage; observed: got everything")
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some("name one of off, errors or usage")
    );
    for level in [Level::Off, Level::Errors, Level::Usage] {
        let name = format!("{level:?}").to_lowercase();
        assert_eq!(Level::parse(&format!(" {name} "), "wisent-errors-test").map_err(|refused| refused.detail), Ok(level));
    }
}

#[test]
fn a_damaged_consent_file_is_refused_and_nothing_is_sent() {
    let mut case = Case::new("damaged-consent");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let state = case.root.join("state");
    std::fs::create_dir_all(&state).expect("the state directory");
    // Spaced and with a second key, so the file is longer than its object
    // written again compactly: the refusal must name the file's own size.
    let damaged = "{ \"level\" : \"sometimes\",\n  \"answered_at\" : \"never\" }\n";
    std::fs::write(state.join("consent.json"), damaged).expect("a damaged file");
    let refused = telemetry
        .level()
        .expect_err("a level that is none of the three is refused");
    case.note("refusal", json!(refused.detail));
    let path = state.join("consent.json");
    assert_eq!(refused.code.as_str(), "config");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!(
            "reading the telemetry consent from {}: the file is not what telemetry wrote: level \"sometimes\" is not off, errors or usage; observed: the file holds {} bytes",
            path.display(),
            damaged.len()
        ).as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some(format!("answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove {}", path.display()).as_str())
    );
    telemetry.failure(&sample_failure(), None);
    assert_eq!(telemetry.status()["queued"], 0);
    assert_eq!(std::fs::read_to_string(&path).expect("the damaged file"), damaged, "the refused file is left as it was");
    // A file that is not JSON, or JSON but no object, is refused the same way.
    for (text, why) in [
        ("{", serde_json::from_str::<serde_json::Value>("{").expect_err("not JSON").to_string()),
        ("[\"errors\"]", "it is not a JSON object".to_owned()),
    ] {
        std::fs::write(&path, text).expect("a damaged file");
        let refused = telemetry.level().expect_err("a file that is no consent object is refused");
        assert_eq!(
            refused.detail.as_deref(),
            Some(format!(
                "reading the telemetry consent from {}: the file is not what telemetry wrote: {why}; observed: the file holds {} bytes",
                path.display(),
                text.len()
            ).as_str())
        );
    }
}
