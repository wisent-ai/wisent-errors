//! `wisent-errors warnings list`, `warnings page` and `warnings check`: the
//! warnings the crate's command line declares, listed as JSON with each
//! warning linked to its entry on docs/command-line.md, that page's section
//! printed as the page holds it, and a warnings listing held to the
//! declaration rules of the Rust runtime, as a product's CI holds the
//! listing its own `warnings list` printed. The warning itself, shown
//! before `telemetry off` drops waiting events and nothing done without
//! `--yes`, is driven in tests/telemetry/consent.rs.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test warnings
//!
//! - Rule 4: the three commands are the crate's real command line,
//!   `env!("CARGO_BIN_EXE_wisent-errors")`, run as a process with its
//!   environment cleared and given only HOME, XDG_* and TMPDIR inside the
//!   case's own directory under `CARGO_TARGET_TMPDIR`. They read no product
//!   and no backend; the listing `warnings check` reads is what `warnings
//!   list` printed, changed only where a step shows a refusal. No case
//!   calls the library.
//! - Rule 5: each run's exit status and whole output are asserted, the page
//!   it prints is held to docs/command-line.md read from disk, and the
//!   case's directory is read back after each run: nothing is written, and
//!   every listing `warnings check` reads is left as it was.
//! - Rule 7: one test per command, each its success and its refusals.
//!
//! The expected listing is the declaration in
//! rust/src/telemetry/consent/mod.rs and catalogue/failures/telemetry.json
//! as the command prints it, and each refusal and problem is its catalogue
//! or declaration-rule template (catalogue/declaration.json) rendered whole
//! with the values the case gives: the command could not be built where
//! these cases were written.

use std::path::PathBuf;
use std::process::Command;

use serde_json::{json, Value};

/// A command that ran, EXIT_SUCCESS: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const SUCCESS: i32 = 0;
/// A command line refused for its own form, as clap's usage errors exit:
/// https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit
const USAGE: i32 = 2;
/// A command that failed for anything but its own form, EXIT_FAILURE:
/// https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const FAILURE: i32 = 1;

const PAGE: &str = "https://github.com/wisent-ai/wisent-errors/blob/main/docs/command-line.md";

/// A directory of the case's own, holding its home and temporary directory.
struct Case {
    root: PathBuf,
}

impl Case {
    fn new(name: &str) -> Self {
        let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("warnings").join(format!("{name}-{}", std::process::id()));
        if let Err(error) = std::fs::remove_dir_all(&root) {
            assert_eq!(error.kind(), std::io::ErrorKind::NotFound, "{} is there before the case and cannot be removed: {error}", root.display());
        }
        for directory in ["home", "tmp"] {
            std::fs::create_dir_all(root.join(directory)).expect("the case's directories");
        }
        Self { root }
    }

    /// `wisent-errors <words>`: its status, stdout and stderr.
    fn run(&self, words: &[&str]) -> (i32, String, String) {
        let home = self.root.join("home");
        let output = Command::new(env!("CARGO_BIN_EXE_wisent-errors"))
            .args(words)
            .current_dir(&self.root)
            .env_clear()
            .env("HOME", &home)
            .env("XDG_CONFIG_HOME", home.join(".config"))
            .env("XDG_STATE_HOME", home.join(".local/state"))
            .env("XDG_CACHE_HOME", home.join(".cache"))
            .env("XDG_DATA_HOME", home.join(".local/share"))
            .env("TMPDIR", self.root.join("tmp"))
            .output()
            .expect("the wisent-errors command starts");
        let Some(status) = output.status.code() else {
            panic!("wisent-errors {words:?} ended without a status: {:?}", output.status);
        };
        (
            status,
            String::from_utf8(output.stdout).expect("the command prints UTF-8"),
            String::from_utf8(output.stderr).expect("the command says UTF-8"),
        )
    }

    /// Every entry below the case's directory, by its path inside it.
    fn entries(&self) -> Vec<String> {
        let mut found = Vec::new();
        let mut pending = vec![self.root.clone()];
        while let Some(directory) = pending.pop() {
            for entry in std::fs::read_dir(&directory).expect("a directory of the case") {
                let path = entry.expect("an entry of the case").path();
                if path.is_dir() {
                    pending.push(path.clone());
                }
                found.push(path.strip_prefix(&self.root).expect("inside the case").display().to_string());
            }
        }
        found.sort();
        found
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        // A panic here, while a failed test unwinds, would abort the run.
        if let Err(error) = std::fs::remove_dir_all(&self.root) {
            eprintln!("the case directory {} could not be removed: {error}", self.root.display());
        }
    }
}

/// What a fresh case holds: its home and its temporary directory, empty.
fn fresh() -> Vec<String> {
    vec!["home".to_owned(), "tmp".to_owned()]
}

/// The three lines of a refusal of `wisent_errors.command.<step>`.
fn refusal_of(step: &str, sentence: &str, fix: &str, cause: &str) -> String {
    format!(
        "Error: {sentence}\nfix: {fix}\ncause: wisent_errors.command.{step}.{cause}; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/command.md#wisent_errors-command-{step}-{cause}\n"
    )
}

/// The three lines of a refusal of `wisent_errors.command.arguments`.
fn refusal(sentence: &str, fix: &str, cause: &str) -> String {
    refusal_of("arguments", sentence, fix, cause)
}

/// `warnings list`, in JSON and as text, and an operand it does not take.
#[test]
fn warnings_list_links_each_warning_to_its_page_entry() {
    let case = Case::new("list");
    let (status, stdout, stderr) = case.run(&["warnings", "list"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{stdout}");
    let listed: Value = serde_json::from_str(&stdout).expect("the list is JSON");
    let effect = "turning telemetry off removes the {queued} event(s) waiting in {queue}";
    let consequence = "nothing sends them afterwards and nothing brings them back, so the failures they record never reach the maintainers of {product}";
    let safeguard = "keep them with `{product} telemetry export <file>`, which writes them as they would have been sent, or send them first with `{product} telemetry flush`";
    let test = "tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events";
    let doc = format!("{PAGE}#wisent-errors-telemetry-consent-warning-queue-dropped");
    assert_eq!(
        listed,
        json!([{
            "operation": "wisent-errors.telemetry.consent",
            "entries": ["<product> telemetry on|off", "Telemetry::ask", "Telemetry::set_level"],
            "summary": "keep the level of telemetry the user chose",
            "warnings": [{
                "id": "queue-dropped",
                "hazard": "irreversible",
                "effect": effect,
                "consequence": consequence,
                "safeguard": safeguard,
                "confirm": "rerun with --yes",
                "test": test,
                "doc": doc,
            }],
        }])
    );
    assert_eq!(case.entries(), fresh(), "listing writes nothing");

    let (status, stdout, stderr) = case.run(&["--text", "warnings", "list"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{stdout}");
    let prefix = "[0].warnings[0]";
    assert_eq!(
        stdout,
        [
            "[0].entries[0]: <product> telemetry on|off".to_owned(),
            "[0].entries[1]: Telemetry::ask".to_owned(),
            "[0].entries[2]: Telemetry::set_level".to_owned(),
            "[0].operation: wisent-errors.telemetry.consent".to_owned(),
            "[0].summary: keep the level of telemetry the user chose".to_owned(),
            format!("{prefix}.confirm: rerun with --yes"),
            format!("{prefix}.consequence: {consequence}"),
            format!("{prefix}.doc: {doc}"),
            format!("{prefix}.effect: {effect}"),
            format!("{prefix}.hazard: irreversible"),
            format!("{prefix}.id: queue-dropped"),
            format!("{prefix}.safeguard: {safeguard}"),
            format!("{prefix}.test: {test}"),
            String::new(),
        ]
        .join("\n")
    );

    let (status, stdout, stderr) = case.run(&["warnings", "list", "consent"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the operands of `wisent-errors warnings list`: the command takes no operand, and \"consent\" is more than it reads; observed: its operands were [\"consent\"]",
            "drop \"consent\", or quote an operand that holds spaces as one word, as in `wisent-errors warnings list`",
            "operand-extra",
        )
    );
    assert_eq!(case.entries(), fresh(), "a refused listing writes nothing");
}

/// `warnings page` prints the section docs/command-line.md holds, whole;
/// an option it does not take is refused.
#[test]
fn warnings_page_prints_the_section_the_command_line_page_holds() {
    let case = Case::new("page");
    let (status, stdout, stderr) = case.run(&["warnings", "page"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{stdout}");
    let page = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../docs/command-line.md");
    let written = std::fs::read_to_string(&page).expect("docs/command-line.md");
    let section = stdout.strip_suffix('\n').expect("the page ends its last line");
    assert!(section.starts_with("## `wisent-errors.telemetry.consent`\n"), "{section}");
    assert!(
        section.contains("\n<a id=\"wisent-errors-telemetry-consent-warning-queue-dropped\"></a>\n"),
        "the entry the listing links to is anchored: {section}"
    );
    assert!(written.contains(section), "{} holds the section the command prints:\n{section}", page.display());
    assert_eq!(case.entries(), fresh(), "the page writes nothing");

    let (status, stdout, stderr) = case.run(&["warnings", "page", "--json"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the options of `wisent-errors warnings page`: \"--json\" is not an option the command takes; observed: its options are none",
            "drop \"--json\", or write in its place an option the command takes, as in `wisent-errors warnings page`",
            "option-unknown",
        )
    );
}

/// `warnings check` passing the listing `warnings list` printed, then
/// without its file, with a document that is no listing, with a field of
/// the wrong type, and with a warning declared twice, one with an empty
/// safeguard, one with a test that is no test path and one with a hazard
/// the rules do not know.
#[test]
fn warnings_check_holds_each_warning_to_the_declaration_rules() {
    let case = Case::new("check");
    let write = |name: &str, text: &str| std::fs::write(case.root.join(name), text).expect("a listing of the case");
    let read = |name: &str| std::fs::read_to_string(case.root.join(name)).expect("a listing of the case");
    let listing_fix = "name the file `<product> warnings list` printed, or print it again with `<product> warnings list`";

    let (status, listing, stderr) = case.run(&["warnings", "list"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{listing}");
    write("warnings.json", &listing);
    let (status, stdout, stderr) = case.run(&["warnings", "check", "warnings.json"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{stdout}");
    assert_eq!(serde_json::from_str::<Value>(&stdout).expect("JSON"), json!({ "functionalities": 1, "warnings": 1 }));
    assert_eq!(read("warnings.json"), listing, "the check leaves the listing as it was");
    let mut held = fresh();
    held.push("warnings.json".to_owned());
    held.sort();
    assert_eq!(case.entries(), held, "the check writes nothing");

    let (status, stdout, stderr) = case.run(&["warnings", "check"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the operands of `wisent-errors warnings check`: the command takes the listing `<product> warnings list` printed and was given none; observed: its operands were []",
            "give the listing `<product> warnings list` printed, as in `wisent-errors warnings check <warnings-list.json>`",
            "operand-missing",
        )
    );

    // One functionality's object, not the list `warnings list` prints.
    let single = r#"{"operation": "example.item.purge"}"#;
    write("single.json", single);
    let (status, stdout, stderr) = case.run(&["warnings", "check", "single.json"]);
    assert_eq!((status, stdout.as_str()), (FAILURE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal_of(
            "check",
            "reading the warnings listing single.json: the document is not a list of functionalities as `warnings list` prints them; observed: the document holds the object {\"operation\":\"example.item.purge\"}",
            listing_fix,
            "input-shape-invalid",
        )
    );
    assert_eq!(read("single.json"), single);

    // A hazard written as a number.
    let mut numbered: Value = serde_json::from_str(&listing).expect("the listing");
    numbered[0]["warnings"][0]["hazard"] = json!(7);
    let numbered = numbered.to_string();
    write("numbered.json", &numbered);
    let (status, stdout, stderr) = case.run(&["warnings", "check", "numbered.json"]);
    assert_eq!((status, stdout.as_str()), (FAILURE, ""), "{stderr}");
    let place = "functionality 1 (wisent-errors.telemetry.consent)'s warning 1's \"hazard\"";
    assert_eq!(
        stderr,
        refusal_of(
            "check",
            &format!("reading the warnings listing numbered.json: {place} is not a text; observed: {place} holds the number 7"),
            listing_fix,
            "input-shape-invalid",
        )
    );
    assert_eq!(read("numbered.json"), numbered);

    // The warning with an empty safeguard, then again with a test that is
    // no test path and a hazard the rules do not know.
    let mut broken: Value = serde_json::from_str(&listing).expect("the listing");
    let mut again = broken[0]["warnings"][0].clone();
    again["test"] = json!("purge.sh");
    again["hazard"] = json!("scary");
    broken[0]["warnings"][0]["safeguard"] = json!(" ");
    match broken[0]["warnings"].as_array_mut() {
        Some(warnings) => warnings.push(again),
        None => panic!("the listing lists its warnings: {listing}"),
    }
    let broken = broken.to_string();
    write("broken.json", &broken);
    let (status, stdout, stderr) = case.run(&["warnings", "check", "broken.json"]);
    assert_eq!((status, stdout.as_str()), (FAILURE, ""), "{stderr}");
    let operation = "operation wisent-errors.telemetry.consent";
    let problems = [
        format!("(1) {operation}: warning queue-dropped: hazard \"scary\" is not one of irreversible, overwrites, cuts-off-access, exposes-secret, external-change, costs-money; pick the loss the caller cannot take back"),
        format!("(2) {operation}: warning queue-dropped: `safeguard` is empty; write what keeps a way back, done before confirming"),
        format!("(3) {operation}: warning queue-dropped is declared twice; keep one declaration per id"),
        format!("(4) {operation}: warning queue-dropped: test \"purge.sh\" is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it"),
    ];
    assert_eq!(
        stderr,
        refusal_of(
            "check",
            &format!("holding the warnings broken.json declares to the declaration rules: 4 problem(s) in the declarations: {}; observed: 2 warning(s) of 1 functionality(ies) read", problems.join(" ")),
            "change each declaration as its problem says, in the product's code, then print the listing again with `<product> warnings list`",
            "warnings-invalid",
        )
    );
    assert_eq!(read("broken.json"), broken, "a refused check leaves the listing as it was");
}
