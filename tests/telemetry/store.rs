//! The store says what it could not keep, and export gives back exactly the
//! queue.

use serde_json::{json, Value};
use wisent_errors::telemetry::Level;

use crate::{sample_failure, Case};

#[test]
fn an_unwritable_directory_is_named_and_nothing_is_lost_silently() {
    let mut case = Case::new("unwritable");
    let blocker = case.root.join("a-file");
    std::fs::write(&blocker, "not a directory").expect("the blocking file");
    std::env::set_var("WISENT_TELEMETRY_HOME", blocker.join("telemetry"));
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .set_level(Level::Errors)
        .expect_err("a directory under a file cannot be made");
    case.note(
        "refusal",
        json!({ "detail": refused.detail, "remedy": refused.remedy }),
    );
    assert_eq!(refused.code.as_str(), "config");
    let detail = refused.detail.expect("a sentence");
    assert!(
        detail.contains("a-file"),
        "the directory is named: {detail}"
    );
    assert!(refused
        .remedy
        .expect("a fix")
        .contains("WISENT_TELEMETRY_HOME"));
    telemetry.failure(&sample_failure(), None);
}

#[test]
fn export_writes_the_queue_as_it_will_be_sent() {
    let mut case = Case::new("export");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), None);
    telemetry.failure(&sample_failure(), None);
    let file = case.root.join("exported.json");
    let count = telemetry.export(&file).expect("the export is written");
    let exported: Value =
        serde_json::from_str(&std::fs::read_to_string(&file).expect("the export")).expect("JSON");
    case.note("exported", exported.clone());
    assert_eq!(count, 2);
    assert_eq!(
        exported,
        Value::Array(telemetry.queued().expect("the queue reads"))
    );
}
