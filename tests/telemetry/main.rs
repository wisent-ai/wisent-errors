//! The telemetry and support commands of the `wisent-errors` command line
//! (rust/src/bin/wisent-errors, docs/command-line.md), driven as a process
//! the way a product drives them, and the command line's own refusals.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry
//!
//! Each case is a directory of its own under `CARGO_TARGET_TMPDIR`, holding
//! the product file the case names with `--product` (example-product, app
//! example-product-cli, version 1.0.0: the documented input a product of any
//! language gives the command), a home and a temporary directory. Every run
//! is `env!("CARGO_BIN_EXE_wisent-errors")` started with its environment
//! cleared, then given only HOME, XDG_CONFIG_HOME, XDG_STATE_HOME,
//! XDG_CACHE_HOME, XDG_DATA_HOME and TMPDIR inside the case, TZ when this
//! process has one (so the child keeps this host's local time), and
//! `WISENT_TELEMETRY_HOME` naming `<home>/telemetry`. After each step a case
//! reads back its exit status, its whole stderr and the files the command
//! left in that directory. A case appends what each run did to
//! `telemetry/report-<pid>.json` under `CARGO_TARGET_TMPDIR`, headed by the
//! source revision and the uncommitted changes, and removes its directory
//! when done.
//!
//! How this file and the files under it keep the test contract:
//!
//! - Rule 4 (the real product, the real flow): every case starts the
//!   crate's real command line as a process and reads back what it printed
//!   and what it left on disk; no case calls the library. The collector
//!   and the support service are the real ones (`WISENT_TELEMETRY_TEST_COLLECTOR`,
//!   `WISENT_TELEMETRY_TEST_APP_ID`, `WISENT_TELEMETRY_TEST_FAILING_COLLECTOR`,
//!   `WISENT_SUPPORT_TEST_URL`, `WISENT_SUPPORT_TEST_AGENT_TOKEN`); a case
//!   that needs one and is not given it fails with `blocked:` naming the
//!   variable, never passes. What is refused before anything is sent
//!   (nothing listening on the discard port, a plain-http address) needs
//!   none.
//! - Rule 8 (isolation through the environment): the variables above are
//!   the whole environment of the command. `WISENT_TELEMETRY_HOME` is the
//!   product's own override of where telemetry keeps its files;
//!   `WISENT_TELEMETRY_COLLECTOR_URL` and `WISENT_SUPPORT_URL` are its own
//!   overrides of the collector and the support service, set by the cases
//!   that reach one. The product has no other backend: no registry, no
//!   configuration file, nothing else it reads or writes. The stado-wait
//!   register each send stands in is under the case's HOME.
//! - Rule 11 (the companion support cases): support.rs drives `support
//!   report` and `support status` through the command line like every
//!   other case; the only requests it makes itself are a support agent's
//!   own (listing the tickets and replying with
//!   `WISENT_SUPPORT_TEST_AGENT_TOKEN`, read from the environment and sent
//!   in a header, never on a command line), the other side of the real flow
//!   whose reply `support status` must read back. That is the real
//!   component, not a stand-in for one.
//!
//! The command could not be built where these cases were written, so no
//! sentence here was copied from a run of it: each expected refusal is its
//! catalogue template (catalogue/failures/command.json, telemetry.json,
//! cli-output.json) rendered whole with the values the case observes, and
//! what the operating system, the collector and support say is read by
//! asking them the same way, or is the one part of a sentence read as part.

mod consent;
mod delivery;
mod queued;
mod store;
mod support;

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{LazyLock, Mutex};

use serde_json::{json, Value};

/// A command that ran, EXIT_SUCCESS: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
pub const SUCCESS: i32 = 0;
/// A command that failed, EXIT_FAILURE: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
pub const FAILURE: i32 = 1;
/// A command line refused for its own form, as clap's usage errors exit:
/// https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit
pub const USAGE: i32 = 2;
/// A failure worth running again unchanged, EX_UNAVAILABLE:
/// https://man.freebsd.org/cgi/man.cgi?query=sysexits
pub const RETRY: i32 = 69;

/// The product the cases' product file names.
pub const PRODUCT: &str = "example-product";
pub const APP: &str = "example-product-cli";
pub const VERSION: &str = "1.0.0";

/// Every command, as the command line's refusals list them.
pub const COMMANDS: &str = "telemetry status, telemetry level, telemetry on, telemetry off, telemetry failure, telemetry command, telemetry help, telemetry show, telemetry events, telemetry export, telemetry flush, support report, support status, doctor, doctor check, errors list, errors page, warnings list, warnings page, warnings check";

/// The discard port on loopback, where nothing listens on a host that runs
/// no discard service: https://www.rfc-editor.org/rfc/rfc863
pub const NOTHING_LISTENS: &str = "http://127.0.0.1:9";

/// The line a refusal of `operation`'s `cause` ends with: the declared
/// cause and its entry on its page under docs/errors/.
pub fn cause(operation: &str, cause: &str, page: &str) -> String {
    format!(
        "cause: {operation}.{cause}; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/{page}.md#{}-{cause}",
        operation.replace('.', "-")
    )
}

/// The three lines of a refusal, as the command prints them.
pub fn refusal(sentence: &str, fix: &str, operation: &str, cause_id: &str, page: &str) -> Vec<String> {
    vec![format!("Error: {sentence}"), format!("fix: {fix}"), cause(operation, cause_id, page)]
}

/// What one run of the command did.
pub struct Ran {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

/// The words each line a stado-wait wait writes on stderr begins with (its
/// documented `line::announced`): the send to the collector or to support
/// is a wait, and these lines are the wait's, not the command's.
const WAIT_LINES: &[&str] = &["czekam: ", "koniec czekania: ", "blad czekania: "];

impl Ran {
    /// What the command itself said on stderr, a line each, the lines of
    /// its waits left out.
    pub fn said(&self) -> Vec<String> {
        self.stderr
            .lines()
            .filter(|line| !WAIT_LINES.iter().any(|wait| line.starts_with(wait)))
            .map(str::to_owned)
            .collect()
    }

    /// Standard output, read as the JSON document the command printed.
    pub fn json(&self) -> Value {
        match serde_json::from_str(&self.stdout) {
            Ok(document) => document,
            Err(error) => panic!("the command printed no JSON ({error}): {}", self.stdout),
        }
    }

    /// The command exited with `status`, printed nothing, and said exactly
    /// `lines` on stderr.
    pub fn refused(&self, status: i32, lines: &[String]) {
        assert_eq!((self.status, self.said()), (status, lines.to_vec()), "stdout: {}", self.stdout);
        assert_eq!(self.stdout, "", "a refused command prints nothing on stdout");
    }

    /// The command exited 0 and said nothing on stderr; its document.
    pub fn succeeded(&self) -> Value {
        assert_eq!((self.status, self.said()), (SUCCESS, Vec::<String>::new()), "stdout: {}", self.stdout);
        self.json()
    }

    /// The command exited with `status` and said exactly `lines` on stderr
    /// after printing its document: a flush prints what it sent, then why it
    /// stopped; a reported failure prints the status, then what telemetry
    /// itself could not do. Its document.
    pub fn ended(&self, status: i32, lines: &[String]) -> Value {
        assert_eq!((self.status, self.said()), (status, lines.to_vec()), "stdout: {}", self.stdout);
        self.json()
    }
}

pub struct Case {
    /// The case's own directory, where the command runs.
    pub root: PathBuf,
    pub home: PathBuf,
    /// `WISENT_TELEMETRY_HOME`: where the product's telemetry is kept.
    pub state: PathBuf,
    /// The file `--product` names.
    pub product: PathBuf,
    name: &'static str,
    set: Vec<(&'static str, OsString)>,
    notes: Vec<Value>,
}

impl Case {
    /// A case whose product file names `app` as the app id.
    pub fn for_app(name: &'static str, app: &str) -> Self {
        let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
            .join("telemetry")
            .join(format!("{name}-{}", std::process::id()));
        match std::fs::remove_dir_all(&root) {
            Err(error) if error.kind() != std::io::ErrorKind::NotFound => panic!("{} is there before the case and cannot be removed: {error}", root.display()),
            _ => {}
        }
        let home = root.join("home");
        for directory in [&home, &root.join("tmp")] {
            std::fs::create_dir_all(directory).expect("the case's directories");
        }
        let product = root.join("product.json");
        std::fs::write(&product, json!({ "id": PRODUCT, "app_id": app, "version": VERSION }).to_string()).expect("the product file");
        Self { state: home.join("telemetry"), root, home, product, name, set: Vec::new(), notes: Vec::new() }
    }

    pub fn new(name: &'static str) -> Self {
        Self::for_app(name, APP)
    }

    /// Give the command `variable` from now on.
    pub fn set(&mut self, variable: &'static str, value: impl Into<OsString>) {
        self.unset(variable);
        self.set.push((variable, value.into()));
    }

    /// Stop giving the command `variable`.
    pub fn unset(&mut self, variable: &'static str) {
        self.set.retain(|(name, _)| *name != variable);
    }

    /// Run `wisent-errors --product <the case's file> <words>`.
    pub fn run(&mut self, words: &[&str]) -> Ran {
        let product = self.product.display().to_string();
        let mut all = vec!["--product", product.as_str()];
        all.extend_from_slice(words);
        self.bare(&all)
    }

    /// Run `wisent-errors <words>`, naming no product.
    pub fn bare(&mut self, words: &[&str]) -> Ran {
        let mut command = Command::new(env!("CARGO_BIN_EXE_wisent-errors"));
        command
            .args(words)
            .current_dir(&self.root)
            .env_clear()
            .env("HOME", &self.home)
            .env("XDG_CONFIG_HOME", self.home.join(".config"))
            .env("XDG_STATE_HOME", self.home.join(".local/state"))
            .env("XDG_CACHE_HOME", self.home.join(".cache"))
            .env("XDG_DATA_HOME", self.home.join(".local/share"))
            .env("TMPDIR", self.root.join("tmp"))
            .env("WISENT_TELEMETRY_HOME", &self.state);
        if let Some(zone) = std::env::var_os("TZ") {
            command.env("TZ", zone);
        }
        for (variable, value) in &self.set {
            command.env(variable, value);
        }
        let output = command.output().expect("the wisent-errors command starts");
        let ran = Ran {
            status: match output.status.code() {
                Some(status) => status,
                None => panic!("wisent-errors {words:?} ended without a status: {:?}", output.status),
            },
            stdout: String::from_utf8(output.stdout).expect("the command prints UTF-8"),
            stderr: String::from_utf8(output.stderr).expect("the command says UTF-8"),
        };
        self.notes.push(json!({ "words": words, "status": ran.status, "stdout": ran.stdout, "stderr": ran.stderr }));
        ran
    }

    /// The file at `relative` under the telemetry directory, as text.
    pub fn read(&self, relative: &str) -> String {
        let path = self.state.join(relative);
        match std::fs::read_to_string(&path) {
            Ok(text) => text,
            Err(error) => panic!("{} cannot be read: {error}", path.display()),
        }
    }

    /// The JSON file at `relative` under the telemetry directory.
    pub fn json(&self, relative: &str) -> Value {
        match serde_json::from_str(&self.read(relative)) {
            Ok(document) => document,
            Err(error) => panic!("{relative} is not JSON: {error}"),
        }
    }

    /// Whether anything is at `relative` under the telemetry directory.
    pub fn holds(&self, relative: &str) -> bool {
        self.state.join(relative).symlink_metadata().is_ok()
    }

    /// Every event file in the queue, read from disk, oldest first: the order
    /// the command sends them in, by `occurredAt` and then by file name.
    pub fn queued(&self) -> Vec<Value> {
        let queue = self.state.join("queue");
        let entries = match std::fs::read_dir(&queue) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Vec::new(),
            Err(error) => panic!("{} cannot be listed: {error}", queue.display()),
        };
        let mut events: Vec<(PathBuf, Value)> = entries
            .map(|entry| entry.expect("a queue entry").path())
            .filter(|path| path.extension().is_some_and(|extension| extension == "json"))
            .map(|path| {
                let text = std::fs::read_to_string(&path).expect("a queued event");
                (path, serde_json::from_str(&text).expect("a queued event is JSON"))
            })
            .collect();
        events.sort_by(|left, right| {
            left.1["occurredAt"].as_str().cmp(&right.1["occurredAt"].as_str()).then_with(|| left.0.cmp(&right.0))
        });
        events.into_iter().map(|(_, event)| event).collect()
    }

    /// The events of the queue named `name`, their properties each.
    pub fn signals(&self, name: &str) -> Vec<Value> {
        self.queued()
            .into_iter()
            .filter(|event| event["eventName"] == name)
            .map(|event| event["properties"].clone())
            .collect()
    }

    pub fn note(&mut self, what: &str, value: Value) {
        self.notes.push(json!({ "what": what, "value": value }));
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        record(json!({
            "case": self.name,
            "passed": !std::thread::panicking(),
            "runs": self.notes,
        }));
        // A panic here, while a failed test unwinds, would abort the run.
        if let Err(error) = std::fs::remove_dir_all(&self.root) {
            eprintln!("the case directory {} could not be removed: {error}", self.root.display());
        }
    }
}

/// The real collector the delivery cases send to; without it they are
/// blocked, never passed.
pub fn collector() -> String {
    match std::env::var("WISENT_TELEMETRY_TEST_COLLECTOR") {
        Ok(address) => address,
        Err(error) => panic!(
            "blocked: WISENT_TELEMETRY_TEST_COLLECTOR names no collector ({error}); set it to the Echo app collector, \
             https://<echo web>/api/analytics/mobile/collect: these cases run against the real one"
        ),
    }
}

/// The address `collector` answers on, with `path` in place of its own: an
/// address that answers and is not a collector or support.
pub fn elsewhere(path: &str) -> String {
    let real = collector();
    let origin = &real[..real.find("/api/").expect("the collector address has the /api/ path")];
    format!("{origin}{path}")
}

/// What the operating system answers a read of `path` with, asked the way
/// the command asks it.
pub fn os_read(path: &Path) -> String {
    std::fs::read(path).expect_err("the read is refused").to_string()
}

/// The middle of `text` between the exact `prefix` and `suffix`, which it
/// must hold: the words of the collector, support or the transport inside
/// a sentence otherwise compared whole.
pub fn between<'a>(text: &'a str, prefix: &str, suffix: &str) -> &'a str {
    let Some(middle) = text.strip_prefix(prefix).and_then(|rest| rest.strip_suffix(suffix)) else {
        panic!("{text:?} is not {prefix:?}…{suffix:?}");
    };
    middle
}

/// The command line itself (`wisent-errors [--product <file>] <command>`):
/// no command, one it does not have, an option the command does not take,
/// `--product` with no file, no product, a product file that is absent or
/// names a field wrongly (left as it was, and no telemetry written), and
/// the product file it reads.
#[test]
fn the_command_line_says_which_word_it_cannot_read() {
    let mut case = Case::new("command-line");
    let arguments = "wisent_errors.command.arguments";
    let product = "wisent_errors.command.product";

    // No command: only an option, or nothing.
    let ran = case.bare(&["--text"]);
    ran.refused(USAGE, &refusal(
        &format!("reading the command wisent-errors was asked to run: the command line names no command, only options or nothing; observed: the arguments were [\"--text\"]; the commands are {COMMANDS}"),
        "name one of the commands after the options, as in `wisent-errors --product <file> telemetry status`",
        arguments, "command-absent", "command",
    ));

    // A group's word with a command it does not have, and a word that is no command.
    for (words, tried) in [(&["telemetry", "sometimes"][..], "\"telemetry sometimes\""), (&["frobnicate"][..], "\"frobnicate\"")] {
        case.bare(words).refused(USAGE, &refusal(
            &format!("reading the command {tried}: wisent-errors has no command of that name; observed: the commands are {COMMANDS}"),
            &format!("name one of {COMMANDS}"),
            arguments, "command-unknown", "command",
        ));
    }

    // An option the command does not take.
    case.run(&["doctor", "--colour"]).refused(USAGE, &refusal(
        "reading the options of `wisent-errors doctor`: \"--colour\" is not an option the command takes; observed: its options are --json",
        "drop \"--colour\", or write in its place an option the command takes, as in `wisent-errors --product <file> doctor [--json]`",
        arguments, "option-unknown", "command",
    ));

    // --product as the last word.
    case.bare(&["telemetry", "status", "--product"]).refused(USAGE, &refusal(
        "reading the option --product: the option takes a value and is the last word of the command line; observed: the arguments were [\"telemetry\",\"status\",\"--product\"]",
        "give its value right after it, as in `--product <file>`",
        arguments, "option-value-missing", "command",
    ));

    // A command that speaks for a product, with no product named.
    case.bare(&["telemetry", "status"]).refused(USAGE, &refusal(
        "running `wisent-errors telemetry status`: the command speaks for a product and no --product names the product's file; observed: the arguments were [\"telemetry\",\"status\"]",
        "name the product's file before the command, as in `wisent-errors --product product.json telemetry status`: a JSON object with its id, app_id and version",
        product, "product-unnamed", "command",
    ));

    // A product file that is not there: the reader of JSON inputs refuses it.
    let absent = case.root.join("absent.json");
    let missing = std::fs::metadata(&absent).expect_err("nothing is there").to_string();
    let entries = std::fs::read_dir(&case.root).expect("the case directory").count();
    let shown = absent.display().to_string();
    case.bare(&["--product", shown.as_str(), "telemetry", "status"]).refused(USAGE, &refusal(
        &format!("reading the JSON input {shown}: no file is at that path; observed: {shown} cannot be examined ({missing}); {} exists and holds {entries} entries; the operating system answered {}", case.root.display(), os_read(&absent)),
        &format!("name a file that exists, or write it first; a relative path is read from {}", case.root.display()),
        "wisent_errors.cli_output.read_json", "input-absent", "cli-output",
    ));

    // A product file whose fields are not what the command reads, left as it was.
    let example = r#"{"id": "example-product", "app_id": "example-product-cli", "version": "1.0.0", "flush": ["example-product", "telemetry", "flush"]}"#;
    let words = "lowercase words joined by '-'";
    let flush = "a list of the words of the command that sends the queue, its program first, each a text that is not empty";
    for (written, field, wanted, found) in [
        (r#"{"id": "Example Product", "app_id": "example-product-cli", "version": "1.0.0"}"#, "id", words, "the text \"Example Product\""),
        (r#"{"id": "example-product", "app_id": 7, "version": "1.0.0"}"#, "app_id", words, "the number 7"),
        (r#"{"id": "example-product", "app_id": "example-product-cli"}"#, "version", "a version written as text", "nothing, as the file has no such key"),
        (r#"{"id": "example-product", "app_id": "example-product-cli", "version": "1.0.0", "flush": ["example-product", 7]}"#, "flush", flush, "the list [\"example-product\",7]"),
        (r#"{"id": "example-product", "app_id": "example-product-cli", "version": "1.0.0", "flush": "example-product telemetry flush"}"#, "flush", flush, "the text \"example-product telemetry flush\""),
    ] {
        std::fs::write(&case.product, written).expect("the product file");
        let path = case.product.display().to_string();
        case.run(&["telemetry", "status"]).refused(FAILURE, &refusal(
            &format!("reading the product file {path}: its {field} is not {wanted}; observed: {field} holds {found}"),
            &format!("write {field} in {path} as {wanted}, as in {example}"),
            product, "product-field-invalid", "command",
        ));
        assert_eq!(std::fs::read_to_string(&case.product).expect("the product file"), written, "the refused file is left as it was");
    }
    assert!(!case.state.exists(), "no refused command line wrote any telemetry: {}", case.state.display());

    // The product file the command reads: its product is the one status names.
    std::fs::write(&case.product, example).expect("the product file");
    let status = case.run(&["telemetry", "status"]).succeeded();
    assert_eq!((&status["product"], &status["app_id"]), (&json!(PRODUCT), &json!(APP)));
}

fn record(entry: Value) {
    static RUN: LazyLock<PathBuf> = LazyLock::new(|| {
        let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..");
        let git = |words: &[&str]| match Command::new("git").args(words).current_dir(&repository).output() {
            Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).trim().to_owned(),
            Ok(output) => format!("git {words:?} exited {}: {}", output.status, String::from_utf8_lossy(&output.stderr).trim()),
            Err(error) => format!("git {words:?} did not start: {error}"),
        };
        let revision = git(&["rev-parse", "HEAD"]);
        let changes = git(&["status", "--porcelain"]);
        let run = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("telemetry");
        std::fs::create_dir_all(&run).expect("the run directory");
        let report = run.join(format!("report-{}.json", std::process::id()));
        let header = json!({
            "revision": revision,
            "uncommitted": changes,
            "collector": std::env::var("WISENT_TELEMETRY_TEST_COLLECTOR").ok(),
            "app_id": std::env::var("WISENT_TELEMETRY_TEST_APP_ID").ok(),
            "cases": [],
        });
        std::fs::write(&report, header.to_string()).expect("the report");
        report
    });
    // Cases run in parallel; one writes the report at a time.
    static WRITING: Mutex<()> = Mutex::new(());
    // fallback: a case that panicked while writing left the report whole or not at all, so the lock is taken back.
    let _writing = WRITING.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let file: &PathBuf = &RUN;
    let mut report: Value = match std::fs::read_to_string(file).map(|text| serde_json::from_str(&text)) {
        Ok(Ok(report)) => report,
        Ok(Err(error)) => return eprintln!("the telemetry test report {} is not JSON, so this case is not added: {error}", file.display()),
        Err(error) => return eprintln!("the telemetry test report {} cannot be read, so this case is not added: {error}", file.display()),
    };
    if let Some(cases) = report["cases"].as_array_mut() {
        cases.push(entry);
    }
    // Called while a case ends, where a panic would abort the run: a report
    // that cannot be kept is said instead.
    match serde_json::to_string_pretty(&report) {
        Ok(text) => {
            if let Err(error) = std::fs::write(file, text) {
                eprintln!("the telemetry test report {} could not be written: {error}", file.display());
            }
        }
        Err(error) => eprintln!("the telemetry test report could not be serialised: {error}"),
    }
}
