//! The store says what it could not keep or read, and export gives back
//! exactly the queue.

use serde_json::{json, Value};
use wisent_errors::telemetry::Level;

use crate::{sample_failure, Case};

#[test]
fn an_unwritable_directory_is_named_and_nothing_is_lost_silently() {
    let mut case = Case::new("unwritable");
    let blocker = case.root.join("a-file");
    std::fs::write(&blocker, "not a directory").expect("the blocking file");
    let home = blocker.join("telemetry");
    std::env::set_var("WISENT_TELEMETRY_HOME", &home);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .set_level(Level::Errors)
        .expect_err("a directory under a file cannot be made");
    case.note(
        "refusal",
        json!({ "detail": refused.detail, "remedy": refused.remedy }),
    );
    let os = std::fs::create_dir_all(&home).expect_err("a directory under a file cannot be made").to_string();
    assert_eq!(refused.code.as_str(), "config");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!(
            "keeping the telemetry consent in {path}: the telemetry directory could not be written: {os}; observed: directory {home}",
            path = home.join("consent.json").display(),
            home = home.display()
        ).as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some(format!("make {} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME", home.display()).as_str())
    );
    telemetry.failure(&sample_failure(), None);
    assert!(!home.exists(), "nothing was written under the blocking file");
}

#[test]
fn a_file_the_system_refuses_to_read_is_named_with_its_answer() {
    use std::os::unix::fs::PermissionsExt;
    let mut case = Case::new("read-refused");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let state = case.root.join("state");
    std::fs::create_dir_all(&state).expect("the state directory");
    let path = state.join("consent.json");
    let written = r#"{"level":"errors"}"#;
    std::fs::write(&path, written).expect("the consent file");
    // No permission for anyone: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o000)).expect("its permissions can be withdrawn");
    let refused = telemetry.level().expect_err("a file this process may not read is refused");
    let os = std::fs::read(&path).expect_err("the file is refused to this process too").to_string();
    // Owner read and write: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).expect("its permissions can be given back");
    case.note("refusal", json!({ "detail": refused.detail, "remedy": refused.remedy }));
    let shown = path.display();
    assert_eq!(refused.code.as_str(), "config");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!("reading the telemetry consent from {shown}: the operating system refused the read, so what the file holds was never looked at; observed: {shown} is a file of {} bytes; the operating system answered {os}", written.len()).as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some(format!("let the user running wisent-errors-test read it (chmod u+r {shown}), or remove {shown} so telemetry writes it again").as_str())
    );
    assert_eq!(std::fs::read_to_string(&path).expect("the consent file"), written, "the refused file is left as it was");
    // A directory where the file belongs is refused the same way.
    std::fs::remove_file(&path).expect("the consent file is removed");
    std::fs::create_dir(&path).expect("a directory in its place");
    let refused = telemetry.level().expect_err("a directory is no consent file");
    let os = std::fs::read(&path).expect_err("a directory is not read as a file").to_string();
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!("reading the telemetry consent from {shown}: the operating system refused the read, so what the file holds was never looked at; observed: {shown} is a directory; the operating system answered {os}").as_str())
    );
}

#[test]
fn export_writes_the_queue_as_it_will_be_sent() {
    let mut case = Case::new("export");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    // The same failure twice queues both failures and, for the second, the
    // frustration.repeat_failure signal (docs/telemetry.md): three events.
    telemetry.failure(&sample_failure(), None);
    telemetry.failure(&sample_failure(), None);
    let file = case.root.join("exported.json");
    let count = telemetry.export(&file).expect("the export is written");
    let exported: Value =
        serde_json::from_str(&std::fs::read_to_string(&file).expect("the export")).expect("JSON");
    case.note("exported", exported.clone());
    assert_eq!(count, 3);
    let mut names: Vec<&str> = exported
        .as_array()
        .expect("an array")
        .iter()
        .map(|event| event["eventName"].as_str().expect("an event name"))
        .collect();
    names.sort_unstable();
    assert_eq!(names, ["failure", "failure", "frustration.repeat_failure"]);
    assert_eq!(
        exported,
        Value::Array(telemetry.queued().expect("the queue reads"))
    );
}

/// Defect ABBA57B5: status showed an installation or delivery file it could
/// not read as null, as if nothing had been written, while level and queued
/// said unreadable. Absent is null; present and unreadable says why.
#[test]
fn status_names_an_installation_or_delivery_file_it_cannot_read() {
    let mut case = Case::new("status-unreadable");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let state = case.root.join("state");
    std::fs::create_dir_all(&state).expect("the state directory");
    let status = telemetry.status();
    assert_eq!((&status["installation"], &status["last_delivery"]), (&Value::Null, &Value::Null), "no file is null");
    let installation = state.join("installation.json");
    let delivery = state.join("delivery.json");
    std::fs::write(&installation, "[]").expect("an installation file that is no object");
    std::fs::write(&delivery, "{").expect("a delivery file that is not JSON");
    let why = serde_json::from_str::<Value>("{").expect_err("not JSON").to_string();
    let status = telemetry.status();
    case.note("status", status.clone());
    assert_eq!(
        status["installation"],
        json!({ "unreadable": format!("reading the installation id from {}: the file is not what telemetry wrote: it is not a JSON object; observed: the file holds 2 bytes", installation.display()) })
    );
    assert_eq!(
        status["last_delivery"],
        json!({ "unreadable": format!("reading the last delivery from {}: the file is not what telemetry wrote: {why}; observed: the file holds 1 bytes", delivery.display()) })
    );
}
