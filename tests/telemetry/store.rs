//! `wisent-errors --product <file> telemetry status` and `telemetry export
//! <file>`: what the store holds, said file by file as the command finds
//! it, and the queue written to a file as it would be sent.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry store::
//!
//! - Rule 4: both commands run as the crate's command line, a process
//!   (`Case::run`, main.rs); the events are queued by its own `telemetry
//!   failure`, and the files a case damages are the store's own files on
//!   disk, written where the command keeps them, the way a crash or a
//!   person leaves them. No case calls the library.
//! - Rule 5: after every step the case reads back the exit status, the
//!   whole document or the whole three-line refusal, and the files on disk:
//!   the files `status` reads are left byte-identical, the export file holds
//!   exactly the queue read from disk, and a refused export creates nothing
//!   and leaves the queue as it was.
//! - Rule 7: one test per command, each its whole story: `status` from an
//!   empty store through every file it cannot read, `export` from its
//!   missing operand through success to a file it cannot write.

use std::os::unix::fs::PermissionsExt;

use serde_json::{json, Value};

use crate::{refusal, Case, FAILURE, PRODUCT, USAGE};

/// The public collector address every product is built with.
const PUBLIC_COLLECTOR: &str = "https://telemetry.wisent.com/api/analytics/mobile/collect";

/// Queue one failure through the command, as a product reports one.
fn queue_failure(case: &mut Case) {
    case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found", "--detail", "the pairs file is not there"]).succeeded();
}

/// `telemetry status` on an empty store, after an answer and a failure,
/// under DO_NOT_TRACK, with each file it reads damaged, unreadable or a
/// directory, and with a collector address it refuses; and an operand it
/// does not take.
#[test]
fn telemetry_status_says_every_file_as_it_finds_it() {
    let mut case = Case::new("status");

    let fresh = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!(
        fresh,
        json!({
            "product": PRODUCT,
            "app_id": "example-product-cli",
            "level": "unanswered",
            "do_not_track": false,
            "collector": PUBLIC_COLLECTOR,
            "collector_source": "wisent-errors",
            "installation": null,
            "queued": 0,
            "last_delivery": null,
            "directory": "~/telemetry",
        })
    );
    assert!(!case.state.exists(), "status writes nothing: {}", case.state.display());

    case.run(&["telemetry", "status", "now"]).refused(USAGE, &refusal(
        "reading the operands of `wisent-errors telemetry status`: the command takes no operand, and \"now\" is more than it reads; observed: its operands were [\"now\"]",
        "drop \"now\", or quote an operand that holds spaces as one word, as in `wisent-errors --product <file> telemetry status`",
        "wisent_errors.command.arguments", "operand-extra", "command",
    ));

    case.run(&["telemetry", "level", "errors"]).succeeded();
    queue_failure(&mut case);
    let installation = case.json("installation.json")["id"].clone();
    assert!(installation.is_string(), "the installation id is kept: {installation}");
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!(
        (&status["level"], &status["installation"], &status["queued"], &status["last_delivery"]),
        (&json!("errors"), &installation, &json!(case.queued().len()), &Value::Null)
    );
    assert_eq!(case.queued().len(), 1);

    case.set("DO_NOT_TRACK", "1");
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!((&status["do_not_track"], &status["level"]), (&json!(true), &json!("errors")));
    case.unset("DO_NOT_TRACK");

    // Each file status reads, damaged the way a crash or a hand edit leaves it.
    let consent = case.state.join("consent.json");
    let installation_file = case.state.join("installation.json");
    let delivery = case.state.join("delivery.json");
    let (consent_text, installation_text, delivery_text) = (r#"{"level":"sometimes"}"#, "[]", "{");
    std::fs::write(&consent, consent_text).expect("the consent file");
    std::fs::write(&installation_file, installation_text).expect("the installation file");
    std::fs::write(&delivery, delivery_text).expect("the delivery file");
    let decoder = serde_json::from_str::<Value>(delivery_text).expect_err("not JSON").to_string();
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!(
        (&status["level"], &status["installation"], &status["last_delivery"], &status["queued"]),
        (
            &json!({ "unreadable": format!("reading the telemetry consent from {}: the file is not what telemetry wrote: level \"sometimes\" is not off, errors or usage; observed: the file holds {} bytes", consent.display(), consent_text.len()) }),
            &json!({ "unreadable": format!("reading the installation id from {}: the file is not what telemetry wrote: it is not a JSON object; observed: the file holds {} bytes", installation_file.display(), installation_text.len()) }),
            &json!({ "unreadable": format!("reading the last delivery from {}: the file is not what telemetry wrote: {decoder}; observed: the file holds {} bytes", delivery.display(), delivery_text.len()) }),
            &json!(1),
        )
    );
    for (file, text) in [(&consent, consent_text), (&installation_file, installation_text), (&delivery, delivery_text)] {
        assert_eq!(std::fs::read_to_string(file).expect("the damaged file"), text, "status leaves {} as it was", file.display());
    }

    // A consent file this user may not read: no permission for anyone,
    // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    std::fs::set_permissions(&consent, std::fs::Permissions::from_mode(0o000)).expect("its permissions can be withdrawn");
    let denied = std::fs::read(&consent).expect_err("the file is refused to this user").to_string();
    let status = case.run(&["telemetry", "status"]).succeeded();
    // Owner read and write, given back so the case can be removed.
    std::fs::set_permissions(&consent, std::fs::Permissions::from_mode(0o600)).expect("its permissions can be given back");
    assert_eq!(
        status["level"],
        json!({ "unreadable": format!("reading the telemetry consent from {shown}: the operating system refused the read, so what the file holds was never looked at; observed: {shown} is a file of {} bytes; the operating system answered {denied}", consent_text.len(), shown = consent.display()) })
    );
    assert_eq!(std::fs::read_to_string(&consent).expect("the consent file"), consent_text, "the refused file is left as it was");

    // A directory where the consent file belongs.
    std::fs::remove_file(&consent).expect("the consent file is removed");
    std::fs::create_dir(&consent).expect("a directory in its place");
    let directory = std::fs::read(&consent).expect_err("a directory is not read as a file").to_string();
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!(
        status["level"],
        json!({ "unreadable": format!("reading the telemetry consent from {shown}: the operating system refused the read, so what the file holds was never looked at; observed: {shown} is a directory; the operating system answered {directory}", shown = consent.display()) })
    );
    assert!(consent.is_dir(), "status leaves the directory where it is");

    // A collector address status refuses: named, never shown as an address.
    let address = "http://collector.example.invalid/api/analytics/mobile/collect";
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", address);
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!(
        (&status["collector"], &status["collector_source"]),
        (
            &Value::Null,
            &json!({ "refused": format!("reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds {address}") }),
        )
    );
}

/// `telemetry export <file>` without its file, of an empty queue, of a
/// queue of three events, and into a path below a file.
#[test]
fn telemetry_export_writes_the_queue_as_it_will_be_sent() {
    let mut case = Case::new("export");

    case.run(&["telemetry", "export"]).refused(USAGE, &refusal(
        "reading the operands of `wisent-errors telemetry export`: the command takes the file to write the events to and was given none; observed: its operands were []",
        "give the file to write the events to, as in `wisent-errors --product <file> telemetry export <file>`",
        "wisent_errors.command.arguments", "operand-missing", "command",
    ));

    // Nothing queued: the file holds an empty list.
    let exported = case.root.join("events.json");
    let printed = case.run(&["telemetry", "export", "events.json"]).succeeded();
    assert_eq!(printed, json!({ "exported": 0, "file": "events.json" }));
    assert_eq!(std::fs::read_to_string(&exported).expect("the export"), "[]");

    // The same failure twice queues both and, for the second, the
    // frustration.repeat_failure signal (docs/telemetry.md): three events.
    case.run(&["telemetry", "level", "errors"]).succeeded();
    queue_failure(&mut case);
    queue_failure(&mut case);
    let queued = case.queued();
    let mut names: Vec<&str> = queued.iter().map(|event| event["eventName"].as_str().expect("an event name")).collect();
    names.sort_unstable();
    assert_eq!(names, ["failure", "failure", "frustration.repeat_failure"]);
    let printed = case.run(&["telemetry", "export", "events.json"]).succeeded();
    assert_eq!(printed, json!({ "exported": 3, "file": "events.json" }));
    let written: Value = serde_json::from_str(&std::fs::read_to_string(&exported).expect("the export")).expect("the export is JSON");
    assert_eq!(written, Value::Array(queued.clone()), "the export is the queue on disk, in the order it is sent");
    assert_eq!(case.queued(), queued, "the events stay queued");

    // A path below a file: nothing is written, the events stay.
    let blocker = case.root.join("a-file");
    std::fs::write(&blocker, "not a directory").expect("the blocking file");
    let why = std::fs::create_dir_all(&blocker).expect_err("a file is no directory").to_string();
    case.run(&["telemetry", "export", "a-file/events.json"]).refused(FAILURE, &refusal(
        &format!("writing the 3 queued event(s) to a-file/events.json: the file could not be written: {why}; observed: a-file is a file, not a directory; the events stay queued"),
        &format!("name a file in a directory this user can write, as in `{PRODUCT} telemetry export ./events.json`"),
        "wisent-errors.telemetry.export", "export-unwritable", "telemetry",
    ));
    assert_eq!(std::fs::read_to_string(&blocker).expect("the blocking file"), "not a directory");
    assert_eq!(case.queued(), queued, "a refused export keeps every event");
}
