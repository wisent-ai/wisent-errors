//! `wisent-errors errors page`: every functionality the crate's command line
//! runs, as its section of a failure page renders it (`Operation::markdown`,
//! what `stado errors show --markdown` prints for Stado's own), each cause
//! under the class its refusal prints. The catalogue the command runs holds
//! usage causes whose code is not `usage` (every cause of
//! `wisent_errors.command.arguments` is `refused`, `input-absent` of
//! `wisent_errors.cli_output.read_json` is `not_found`): the page used to
//! say them as `Code: refused, exit 2`, a policy refusal, while their refusal
//! is the command line's own; it now says them as `Class: usage`, from the
//! one `Class` the crate names a refusal by.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test errors
//!
//! - Rule 4: the crate's real command line, `env!("CARGO_BIN_EXE_wisent-errors")`,
//!   run as a process with its environment cleared and given only HOME,
//!   XDG_* and TMPDIR inside the case's own directory under
//!   `CARGO_TARGET_TMPDIR`; no case calls the library.
//! - Rule 5: the whole page is compared with the page rendered here from
//!   the declarations on disk (catalogue/failures/**/*.json, the Rust view
//!   of each part, and catalogue/codes.json for which codes are retryable),
//!   in the order the command's own `errors list` prints them; the case's
//!   directory is read back after each run: the page writes nothing.
//! - Rule 6: the command's refusals, an operand and an option it does not
//!   take, are each compared whole with their exit status.
//! - Rule 7: one test, the page command and its story.
//! - Rule 9: the refusals are the catalogue's templates of
//!   `wisent_errors.command.arguments` rendered whole with the values the
//!   case gives; the command could not be built where this case was
//!   written.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::Value;

/// A command that ran, EXIT_SUCCESS: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const SUCCESS: i32 = 0;
/// A command line refused for its own form, as clap's usage errors exit:
/// https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit
const USAGE: i32 = 2;
/// The status a retryable code exits with, EX_UNAVAILABLE:
/// https://man.freebsd.org/cgi/man.cgi?query=sysexits
const RETRY: i32 = 69;
/// The command line's own failure status, EXIT_FAILURE:
/// https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const FAILURE: i32 = 1;

/// The repository, where the declarations the command is generated from live.
fn repository() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..")
}

/// A directory of the case's own, holding its home and temporary directory.
struct Case {
    root: PathBuf,
}

impl Case {
    fn new(name: &str) -> Self {
        let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("errors").join(format!("{name}-{}", std::process::id()));
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

/// The three lines of a refusal of `wisent_errors.command.arguments`.
fn refusal(sentence: &str, fix: &str, cause: &str) -> String {
    format!(
        "Error: {sentence}\nfix: {fix}\ncause: wisent_errors.command.arguments.{cause}; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/command.md#wisent_errors-command-arguments-{cause}\n"
    )
}

/// Every JSON part under `directory`, at any depth.
fn parts(directory: &Path, found: &mut Vec<Value>) {
    for entry in std::fs::read_dir(directory).expect("catalogue/failures/ lists") {
        let path = entry.expect("an entry of catalogue/failures/").path();
        if path.is_dir() {
            parts(&path, found);
        } else if path.extension().is_some_and(|extension| extension == "json") {
            let text = std::fs::read_to_string(&path).expect("a part reads");
            match serde_json::from_str(&text) {
                Ok(part) => found.push(part),
                Err(error) => panic!("{} is JSON: {error}", path.display()),
            }
        }
    }
}

/// Each functionality the Rust runtime declares, by its id, as its part on
/// disk declares it.
fn declared() -> HashMap<String, Value> {
    let mut found = Vec::new();
    parts(&repository().join("catalogue/failures"), &mut found);
    let mut operations = HashMap::new();
    for part in found {
        for operation in part["operations"].as_array().expect("a part lists its operations") {
            let runtimes = operation["runtimes"].as_array().expect("an operation names its runtimes");
            if runtimes.iter().any(|runtime| runtime == "rust") {
                let id = operation["id"].as_str().expect("an operation's id").to_owned();
                operations.insert(id, operation.clone());
            }
        }
    }
    operations
}

/// The codes running the same command again can help, as catalogue/codes.json declares them.
fn retryable_codes() -> Vec<String> {
    let text = std::fs::read_to_string(repository().join("catalogue/codes.json")).expect("catalogue/codes.json reads");
    let codes: Value = serde_json::from_str(&text).expect("catalogue/codes.json is JSON");
    codes["codes"]
        .as_array()
        .expect("the vocabulary lists its codes")
        .iter()
        .filter(|code| code["retryable"] == true)
        .map(|code| code["code"].as_str().expect("a code's name").to_owned())
        .collect()
}

/// `items` as the page lists them, each in backquotes, or `none`.
fn listed(items: &[&str], none: &str) -> String {
    if items.is_empty() {
        return none.to_owned();
    }
    items.iter().map(|item| format!("`{item}`")).collect::<Vec<_>>().join(", ")
}

/// The texts of `value`, a list of strings.
fn texts(value: &Value) -> Vec<&str> {
    value.as_array().expect("a list").iter().map(|item| item.as_str().expect("a text")).collect()
}

/// The section of the page `operation`, as its part declares it, holds.
fn section(operation: &Value, retryable: &[String]) -> String {
    let id = operation["id"].as_str().expect("an id");
    let entries = match &operation["entries"] {
        Value::Object(per_runtime) => texts(&per_runtime["rust"]),
        list => texts(list),
    };
    let uses = texts(&operation["uses"]);
    let causes: Vec<&Value> = operation["causes"]
        .as_array()
        .expect("an operation lists its causes")
        .iter()
        .filter(|cause| cause["tests"]["rust"].is_string())
        .collect();
    let mut text = format!(
        "## `{id}`\n\n{}\n\nStarted through: {}. Uses: {}. Failure catalogue `{id}`: {} declared cause(s) of its own.\n",
        operation["summary"].as_str().expect("a summary"),
        listed(&entries, "run only by the functionalities that use it"),
        listed(&uses, "none"),
        causes.len()
    );
    for cause in causes {
        let field = |name: &str| match cause[name].as_str() {
            Some(text) => text,
            None => panic!("{id}: a cause's {name} is text"),
        };
        let usage = cause["usage"] == true;
        let code = field("code");
        let (class, again) = if usage { ("usage", false) } else { (code, retryable.iter().any(|listed| listed == code)) };
        let exit = if usage {
            USAGE
        } else if let Some(declared) = cause["exit"].as_i64() {
            i32::try_from(declared).expect("an exit status")
        } else if again {
            RETRY
        } else {
            FAILURE
        };
        let retry = if again { "retrying unchanged can help" } else { "retrying unchanged will not help" };
        text.push_str(&format!(
            "\n<a id=\"{anchor}-{cause_id}\"></a>\n\n### `{id}.{cause_id}`\n\n- **What failed:** {failed}\n- **Cause:** {why}\n- **Observed state shown:** {observed}\n- **Fix:** {remedy}\n- **Class:** `{class}`, exit {exit}; {retry}\n- **Test:** `{test}`\n",
            anchor = id.replace('.', "-"),
            cause_id = field("id"),
            failed = field("failed"),
            why = field("cause"),
            observed = field("observed"),
            remedy = field("remedy"),
            test = cause["tests"]["rust"].as_str().expect("the Rust test"),
        ));
    }
    text
}

/// `errors page` says each cause under the class its refusal prints, a
/// usage cause as `usage` whatever code it carries; an operand and an
/// option it does not take are refused.
#[test]
fn errors_page_says_each_cause_under_the_class_its_refusal_prints() {
    let case = Case::new("page");

    // The order the command runs its functionalities in, as it lists them.
    let (status, listing, stderr) = case.run(&["errors", "list"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{listing}");
    let listing: Value = serde_json::from_str(&listing).expect("`errors list` prints JSON");
    let order: Vec<&str> = listing
        .as_array()
        .expect("a list of functionalities")
        .iter()
        .map(|operation| operation["operation"].as_str().expect("a functionality's id"))
        .collect();

    let (status, page, stderr) = case.run(&["errors", "page"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{page}");
    let declared = declared();
    let retryable = retryable_codes();
    let sections: Vec<String> = order
        .iter()
        .map(|id| match declared.get(*id) {
            Some(operation) => section(operation, &retryable),
            None => panic!("no part declares {id}"),
        })
        .collect();
    assert_eq!(page, format!("{}\n", sections.join("\n").trim_end()));
    assert_eq!(case.entries(), fresh(), "the page writes nothing");

    // The defect this page had: a usage cause said under its code.
    let arguments = &declared["wisent_errors.command.arguments"];
    let absent = arguments["causes"]
        .as_array()
        .expect("its causes")
        .iter()
        .find(|cause| cause["id"] == "command-absent")
        .expect("wisent_errors.command.arguments declares command-absent");
    assert_eq!((absent["usage"].clone(), absent["code"].clone()), (Value::Bool(true), Value::from("refused")), "a usage cause carrying a code of its own");
    let entry = page
        .split("### `wisent_errors.command.arguments.command-absent`")
        .nth(1)
        .expect("the page holds command-absent");
    assert!(entry.contains("\n- **Class:** `usage`, exit 2; retrying unchanged will not help\n"), "{entry}");
    assert!(!page.contains("`refused`, exit 2"), "no usage cause is said under its code:\n{page}");

    // An operand the page does not take.
    let (status, stdout, stderr) = case.run(&["errors", "page", "lint"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the operands of `wisent-errors errors page`: the command takes no operand, and \"lint\" is more than it reads; observed: its operands were [\"lint\"]",
            "drop \"lint\", or quote an operand that holds spaces as one word, as in `wisent-errors errors page`",
            "operand-extra",
        )
    );
    assert_eq!(case.entries(), fresh(), "a refused page writes nothing");

    // An option the page does not take.
    let (status, stdout, stderr) = case.run(&["errors", "page", "--json"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the options of `wisent-errors errors page`: \"--json\" is not an option the command takes; observed: its options are none",
            "drop \"--json\", or write in its place an option the command takes, as in `wisent-errors errors page`",
            "option-unknown",
        )
    );
    assert_eq!(case.entries(), fresh(), "a refused page writes nothing");
}
