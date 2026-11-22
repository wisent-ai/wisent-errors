//! `wisent-errors --product <file> telemetry level <off|errors|usage>` (and
//! its spellings `telemetry on`, the errors level, and `telemetry off`): the
//! user's answer kept in `consent.json`, and what the command refuses.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry consent::
//!
//! - Rule 4: the command line runs as a process (`Case::run`, main.rs); the
//!   events it would drop are queued by its own `telemetry failure`, never
//!   written by hand.
//! - Rule 5: after every step the case reads back the exit status, the whole
//!   refusal or warning on stderr, and `consent.json` and the queue on disk:
//!   a refused level writes nothing, an unconfirmed `off` leaves the consent
//!   byte-identical and the event waiting, a confirmed one removes the queue.

use serde_json::json;

use crate::{refusal, Case, FAILURE, PRODUCT, USAGE};

/// Queue one failure through the command, as a product reports one.
fn queue_failure(case: &mut Case) {
    case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found", "--detail", "the pairs file is not there"]).succeeded();
}

/// `telemetry level` without a level or with an unknown one, each level kept
/// and read back, `off` refused until `--yes` while events wait, and a
/// telemetry directory that cannot be written.
#[test]
fn telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events() {
    let mut case = Case::new("consent");

    case.run(&["telemetry", "level"]).refused(USAGE, &refusal(
        "reading the operands of `wisent-errors telemetry level`: the command takes one level: off, errors or usage and was given none; observed: its operands were []",
        "give one level: off, errors or usage, as in `wisent-errors --product <file> telemetry level <off|errors|usage> [--yes]`",
        "wisent_errors.command.arguments", "operand-missing", "command",
    ));
    case.run(&["telemetry", "level", "everything"]).refused(USAGE, &refusal(
        "setting the telemetry level to everything: telemetry knows the levels off, errors and usage; observed: got everything",
        "name one of off, errors or usage",
        "wisent-errors.telemetry.consent", "level-unknown", "telemetry",
    ));
    assert!(!case.state.exists(), "a refused level keeps nothing: {}", case.state.display());

    let status = case.run(&["telemetry", "level", "errors"]).succeeded();
    assert_eq!(status["level"], "errors");
    let consent = case.json("consent.json");
    assert_eq!(consent["level"], "errors");
    assert!(consent["answered_at"].is_string(), "{consent}");

    // One event waits; turning telemetry off would drop it.
    queue_failure(&mut case);
    assert_eq!(case.queued().len(), 1);
    let kept = case.read("consent.json");
    let queue = case.state.join("queue");
    let warned = vec![
        format!(
            "Warning: turning telemetry off removes the 1 event(s) waiting in {}; nothing sends them afterwards and nothing brings them back, so the failures they record never reach the maintainers of {PRODUCT}; nothing was done. Before confirming: keep them with `{PRODUCT} telemetry export <file>`, which writes them as they would have been sent, or send them first with `{PRODUCT} telemetry flush`. To go ahead: rerun with --yes",
            queue.display()
        ),
        "warning: wisent-errors.telemetry.consent.queue-dropped; https://github.com/wisent-ai/wisent-errors/blob/main/docs/command-line.md#wisent-errors-telemetry-consent-warning-queue-dropped".to_owned(),
    ];
    for words in [&["telemetry", "off"][..], &["telemetry", "level", "off"][..]] {
        case.run(words).refused(USAGE, &warned);
        assert_eq!(case.read("consent.json"), kept, "an unconfirmed off keeps the answer as it was");
        assert_eq!(case.queued().len(), 1, "an unconfirmed off drops nothing");
    }

    let status = case.run(&["telemetry", "off", "--yes"]).succeeded();
    assert_eq!((&status["level"], &status["queued"]), (&json!("off"), &json!(0)));
    assert_eq!(case.json("consent.json")["level"], "off");
    assert!(!queue.exists(), "a confirmed off removes the queue");
    // Nothing waits now, so off asks for nothing.
    case.run(&["telemetry", "off"]).succeeded();

    assert_eq!(case.run(&["telemetry", "on"]).succeeded()["level"], "errors");
    assert_eq!(case.json("consent.json")["level"], "errors");
    assert_eq!(case.run(&["telemetry", "level", "usage"]).succeeded()["level"], "usage");
    assert_eq!(case.json("consent.json")["level"], "usage");

    // A telemetry directory below a file cannot be made: the answer is refused
    // naming where it would have been kept.
    let blocker = case.root.join("a-file");
    std::fs::write(&blocker, "not a directory").expect("the blocking file");
    let home = blocker.join("telemetry");
    case.set("WISENT_TELEMETRY_HOME", &home);
    let os = std::fs::create_dir_all(&home).expect_err("a directory under a file cannot be made").to_string();
    case.run(&["telemetry", "level", "errors"]).refused(FAILURE, &refusal(
        &format!("keeping the telemetry consent in {}: the telemetry directory could not be written: {os}; observed: directory {}", home.join("consent.json").display(), home.display()),
        &format!("make {} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME", home.display()),
        "wisent-errors.telemetry.store", "store-unwritable", "telemetry",
    ));
    assert_eq!(std::fs::read_to_string(&blocker).expect("the blocking file"), "not a directory");
    assert!(!home.exists(), "nothing was written below the file");
}
