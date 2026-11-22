//! `wisent-errors --product <file> telemetry failure|command|help`: what a
//! product reports as its commands end, queued under the consent the user
//! gave, and the frustration signals only the reporter can count (a repeat
//! in a row, a usage loop, help asked after a failure).
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry queued::signals::
//!
//! - Rule 4: each command runs as the crate's command line, a process
//!   (`Case::run`, main.rs), as a product of any language reports through
//!   it. No case calls the library.
//! - Rule 5: after every step the case reads the queue and `signals.json`
//!   back from disk (`Case::queued`, `Case::json`), with the exit status and
//!   the whole three-line refusal of what the command refuses, which leaves
//!   the queue as it was.
//! - Rule 7: one test per command, each its whole story: `telemetry
//!   failure` with its refusals, before consent, and its repeats;
//!   `telemetry command` with its refusals, under errors and under usage,
//!   and its loop; `telemetry help` with its refusal and the signal it
//!   counts only under usage.
//! - Rule 9: the command could not be built where these cases were written,
//!   so nothing here is copied from a run of it: each refusal is its
//!   catalogue template (catalogue/failures/command.json, envelope.json)
//!   rendered whole with the values the case gives, and each event is what
//!   rust/src/telemetry/events.rs declares, read back from the queue the
//!   real command wrote. What a clock decides (the seconds between two
//!   runs) is read as a whole number, never pinned.

use serde_json::{json, Value};

use crate::{refusal, Case, USAGE};

const POINT: &str = "example-product.pairs.import";

/// The codes of the fleet's vocabulary, as the refusal lists them.
const CODES: &str = "config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown";

/// `telemetry failure` without its code, with a code the fleet does not
/// have and a failure point that is no dotted path; before the user
/// answers; then the same failure again and again, and another between.
#[test]
fn telemetry_failure_queues_the_failure_and_counts_a_repeat_in_a_row() {
    let mut case = Case::new("failure");
    let usage = "wisent-errors --product <file> telemetry failure <failure-point> <code> [--detail <text>] [--remedy <text>] [--impact <text>] [--cause-id <id>]";

    case.run(&["telemetry", "failure", POINT]).refused(USAGE, &refusal(
        &format!("reading the operands of `wisent-errors telemetry failure`: the command takes a failure point and a code and was given 1; observed: its operands were [\"{POINT}\"]"),
        &format!("give a failure point and a code, as in `{usage}`"),
        "wisent_errors.command.arguments", "operand-missing", "command",
    ));
    case.run(&["telemetry", "failure", POINT, "missing"]).refused(USAGE, &refusal(
        &format!("reading the code of the failure at {POINT}: \"missing\" is not a code of the fleet's vocabulary; observed: the codes are {CODES}"),
        &format!("name one of {CODES}; catalogue/codes.json says what each one means"),
        "wisent_errors.command.arguments", "code-unknown", "command",
    ));
    case.run(&["telemetry", "failure", "example-product..import", "not_found"]).refused(USAGE, &refusal(
        "building the failure envelope of service example-product: segment 2 of the failure point \"example-product..import\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"example-product\",\"\",\"import\"]",
        "drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with Failure::or_fallback",
        "wisent_errors.envelope.build", "failure-point-segment-empty", "envelope",
    ));

    // Before the user answers nothing is queued and nothing is kept.
    let status = case.run(&["telemetry", "failure", POINT, "not_found"]).succeeded();
    assert_eq!((&status["level"], &status["queued"]), (&json!("unanswered"), &json!(0)));
    assert!(!case.state.exists(), "nothing is kept before the user answers: {}", case.state.display());

    case.run(&["telemetry", "level", "errors"]).succeeded();
    let status = case
        .run(&["telemetry", "failure", POINT, "not_found", "--detail", "the pairs file is not there", "--remedy", "put the pairs file back", "--cause-id", "pairs-unreadable"])
        .succeeded();
    assert_eq!(status["queued"], 1);
    let failures = case.signals("failure");
    assert_eq!(
        failures,
        vec![json!({
            "failure_point": POINT,
            "error_code": "not_found",
            "severity": "warning",
            "retryable": false,
            "outage": false,
            "service": "example-product",
            "impact": null,
            "detail": "the pairs file is not there",
            "remedy": "put the pairs file back",
            "cause_id": "pairs-unreadable",
            "context": {},
            "causes": [],
        })]
    );
    assert!(case.signals("frustration.repeat_failure").is_empty(), "a first failure is no repeat");
    assert_eq!(case.json("signals.json")["last_failure"]["consecutive"], 1);

    // The same failure twice more: the second and the third in a row.
    for _ in 0..2 {
        case.run(&["telemetry", "failure", POINT, "not_found"]).succeeded();
    }
    let repeats = case.signals("frustration.repeat_failure");
    let counts: Vec<&Value> = repeats.iter().map(|repeat| &repeat["consecutive"]).collect();
    assert_eq!(counts, [&json!(2), &json!(3)], "{repeats:?}");
    assert!(repeats.iter().all(|repeat| repeat["failure_point"] == POINT && repeat["seconds_since_previous"].is_u64()), "{repeats:?}");
    assert_eq!(case.signals("failure").len(), 3);

    // Another failure between ends the run: the next one is a first again.
    case.run(&["telemetry", "failure", "example-product.model.load", "not_found"]).succeeded();
    case.run(&["telemetry", "failure", POINT, "not_found"]).succeeded();
    assert_eq!(case.signals("frustration.repeat_failure").len(), 2, "another failure in between ends the run");
    assert_eq!(case.json("signals.json")["last_failure"], json!({ "failure_point": POINT, "consecutive": 1, "at": case.json("signals.json")["last_failure"]["at"] }));
    assert_eq!(case.signals("failure").len(), 5);
}

/// `telemetry command` with an exit status or a duration that is no whole
/// number; under errors, where commands are not counted; under usage,
/// where the same usage refusal twice is a loop and a command that ran
/// ends it.
#[test]
fn telemetry_command_queues_usage_and_counts_a_usage_loop() {
    let mut case = Case::new("command");
    let usage = "wisent-errors --product <file> telemetry command <name> <exit-status> <duration-ms>";

    for (operands, what, value) in [
        (["pairs import", "two", "3"], "the exit status", "two"),
        (["pairs import", "2", "-3"], "the duration in milliseconds", "-3"),
    ] {
        let mut words = vec!["telemetry", "command"];
        words.extend(operands);
        case.run(&words).refused(USAGE, &refusal(
            &format!("reading {what} for `wisent-errors telemetry command`: \"{value}\" is not a whole number; observed: its operands were {}", serde_json::to_string(&operands).expect("the operands as JSON")),
            &format!("give {what} as a whole number, as in `{usage}`"),
            "wisent_errors.command.arguments", "number-invalid", "command",
        ));
    }
    assert!(!case.state.exists(), "a refused command line keeps nothing");

    // Under errors a command is no failure: nothing is queued or counted.
    case.run(&["telemetry", "level", "errors"]).succeeded();
    for _ in 0..2 {
        let status = case.run(&["telemetry", "command", "pairs import", "2", "3"]).succeeded();
        assert_eq!(status["queued"], 0);
    }
    assert!(case.queued().is_empty(), "commands are not queued under errors");
    assert!(!case.holds("signals.json"), "commands are not counted under errors");

    // Under usage: each command is queued, and the same usage refusal again is a loop.
    case.run(&["telemetry", "level", "usage"]).succeeded();
    for _ in 0..2 {
        case.run(&["telemetry", "command", "pairs import", "2", "3"]).succeeded();
    }
    assert_eq!(
        case.signals("cli.command"),
        vec![json!({ "command": "pairs import", "exit_status": 2, "duration_ms": 3 }); 2]
    );
    let loops = case.signals("frustration.usage_loop");
    let [usage_loop] = loops.as_slice() else {
        panic!("one usage loop: {loops:?}");
    };
    assert_eq!((&usage_loop["command"], &usage_loop["consecutive"]), (&json!("pairs import"), &json!(2)));
    assert!(usage_loop["seconds_since_previous"].is_u64(), "{usage_loop}");

    // A command that ran ends the loop; the next refusal is a first again.
    case.run(&["telemetry", "command", "pairs import", "0", "3"]).succeeded();
    assert!(case.json("signals.json").get("last_usage_refusal").is_none(), "a command that ran ends the loop");
    case.run(&["telemetry", "command", "pairs import", "2", "3"]).succeeded();
    assert_eq!(case.signals("frustration.usage_loop").len(), 1, "a command that ran ends the loop");
    assert_eq!(case.signals("cli.command").len(), 4);
}

/// `telemetry help` without the command it was asked about; under usage
/// with no failure before it, after a failure, and under errors.
#[test]
fn telemetry_help_after_a_failure_is_counted_under_usage() {
    let mut case = Case::new("help");

    case.run(&["telemetry", "help"]).refused(USAGE, &refusal(
        "reading the operands of `wisent-errors telemetry help`: the command takes the command help was asked about and was given none; observed: its operands were []",
        "give the command help was asked about, as in `wisent-errors --product <file> telemetry help <command>`",
        "wisent_errors.command.arguments", "operand-missing", "command",
    ));

    case.run(&["telemetry", "level", "usage"]).succeeded();
    case.run(&["telemetry", "help", "pairs import"]).succeeded();
    assert!(case.queued().is_empty(), "help with no failure before it is no signal");

    case.run(&["telemetry", "failure", POINT, "not_found"]).succeeded();
    case.run(&["telemetry", "help", "pairs import"]).succeeded();
    let helps = case.signals("frustration.help_after_failure");
    let [help] = helps.as_slice() else {
        panic!("one help after a failure: {helps:?}");
    };
    assert_eq!((&help["command"], &help["failure_point"]), (&json!("pairs import"), &json!(POINT)));
    assert!(help["seconds_since_failure"].is_u64(), "{help}");

    case.run(&["telemetry", "level", "errors"]).succeeded();
    case.run(&["telemetry", "help", "pairs import"]).succeeded();
    assert_eq!(case.signals("frustration.help_after_failure").len(), 1, "help is usage, not counted under errors");
}
