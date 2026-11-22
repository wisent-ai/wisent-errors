//! `wisent-errors --product <file> doctor [--json]`: every functionality of
//! the crate's command line tried now on this machine for the product the
//! product file names, each said as working with what was seen, failing
//! with what failed and its fix, or not tried and why (docs/diagnosis.md);
//! and `wisent-errors doctor check <errors-list.json> <doctor.json>`, which
//! a product's CI runs to hold what its `doctor --json` printed to the
//! functionalities its `errors list --json` declares.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test diagnosis
//!
//! - Rule 4: both are the crate's real command line,
//!   `env!("CARGO_BIN_EXE_wisent-errors")`, run as a process with its
//!   environment cleared and given only HOME, XDG_CONFIG_HOME,
//!   XDG_STATE_HOME, XDG_CACHE_HOME, XDG_DATA_HOME and TMPDIR inside the
//!   case's own directory under `CARGO_TARGET_TMPDIR`, and
//!   `WISENT_TELEMETRY_HOME`, the product's own override of where telemetry
//!   keeps its files (with `WISENT_TELEMETRY_COLLECTOR_URL` and
//!   `WISENT_SUPPORT_URL`, its overrides of the collector and support, set
//!   where a step names one it refuses). The product has no other backend.
//!   The doctor sends nothing, so no collector or support is reached. The
//!   files `doctor check` holds to each other are what the command's own
//!   `errors list --json` and `doctor --json` printed, each changed only
//!   where a step shows a refusal. No case calls the library.
//! - Rule 5: each step reads back the exit status, the whole output or the
//!   whole three-line refusal, and the files on disk: the doctor's probe of
//!   the store leaves the directory it made and nothing in it, a damaged
//!   consent file is left byte-identical, a store below a file is left with
//!   nothing created under the file, and every file `doctor check` reads is
//!   left as it was.
//! - Rule 7: one test per command, each its story: the doctor working,
//!   failing for a user's settings, failing for a store it cannot write, in
//!   JSON, and refusing an operand; `doctor check` passing the doctor's own
//!   findings, then each refusal it can give.
//!
//! The command could not be built where these cases were written: each line
//! expected is the sentence of the probe or of the cause its failure is
//! (catalogue/failures/telemetry.json, command.json, cli-output.json), or
//! the sentence `diagnosis::problems` says, rendered whole with the values
//! the case observes, and what the operating system answers is asked of it
//! the same way.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::{json, Value};

/// A diagnosis where everything works, EXIT_SUCCESS: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const SUCCESS: i32 = 0;
/// A diagnosis where something fails, EXIT_FAILURE: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const FAILURE: i32 = 1;
/// A command line refused for its own form, as clap's usage errors exit:
/// https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit
const USAGE: i32 = 2;

const PRODUCT: &str = "example-product";

/// The case's directory, its home and its product file.
struct Case {
    root: PathBuf,
    home: PathBuf,
    product: PathBuf,
    set: Vec<(&'static str, String)>,
}

impl Case {
    fn new(name: &str) -> Self {
        let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("diagnosis").join(format!("{name}-{}", std::process::id()));
        if let Err(error) = std::fs::remove_dir_all(&root) {
            assert_eq!(error.kind(), std::io::ErrorKind::NotFound, "{} is there before the case and cannot be removed: {error}", root.display());
        }
        let home = root.join("home");
        for directory in [&home, &root.join("tmp")] {
            std::fs::create_dir_all(directory).expect("the case's directories");
        }
        let product = root.join("product.json");
        std::fs::write(&product, json!({ "id": PRODUCT, "app_id": "example-product-cli", "version": "1.0.0" }).to_string()).expect("the product file");
        let state = home.join("telemetry").display().to_string();
        Self { root, home, product, set: vec![("WISENT_TELEMETRY_HOME", state)] }
    }

    fn set(&mut self, variable: &'static str, value: &str) {
        self.unset(variable);
        self.set.push((variable, value.to_owned()));
    }

    fn unset(&mut self, variable: &'static str) {
        self.set.retain(|(name, _)| *name != variable);
    }

    /// `wisent-errors --product <the case's file> <words>`.
    fn run(&self, words: &[&str]) -> (i32, String, String) {
        let product = self.product.display().to_string();
        let mut all = vec!["--product", product.as_str()];
        all.extend_from_slice(words);
        self.bare(&all)
    }

    /// `wisent-errors <words>`: its status, stdout and stderr.
    fn bare(&self, words: &[&str]) -> (i32, String, String) {
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
            .env("TMPDIR", self.root.join("tmp"));
        for (variable, value) in &self.set {
            command.env(variable, value);
        }
        let output = command.output().expect("the wisent-errors command starts");
        let Some(status) = output.status.code() else {
            panic!("wisent-errors {words:?} ended without a status: {:?}", output.status);
        };
        (
            status,
            String::from_utf8(output.stdout).expect("the command prints UTF-8"),
            String::from_utf8(output.stderr).expect("the command says UTF-8"),
        )
    }

    /// The file `name` in the case's directory, as text.
    fn read(&self, name: &str) -> String {
        let path = self.root.join(name);
        match std::fs::read_to_string(&path) {
            Ok(text) => text,
            Err(error) => panic!("{} cannot be read: {error}", path.display()),
        }
    }

    fn write(&self, name: &str, text: &str) {
        std::fs::write(self.root.join(name), text).expect("a file of the case");
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

/// The three lines of a refusal, each ending its line.
fn refusal(sentence: &str, fix: &str, operation: &str, cause: &str, page: &str) -> String {
    format!(
        "Error: {sentence}\nfix: {fix}\ncause: {operation}.{cause}; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/{page}.md#{}-{cause}\n",
        operation.replace('.', "-")
    )
}

/// Every functionality the doctor says, in its order, and why it does not
/// try the ones it skips.
const SAID: [(&str, Option<&str>); 15] = [
    ("wisent_errors.command.arguments", Some("it read this command line to start the diagnosis")),
    ("wisent_errors.command.product", None),
    ("wisent_errors.cli_output.read_json", Some("the product file is read through it, so the product file's line says whether it works")),
    ("wisent-errors.telemetry.consent", None),
    ("wisent-errors.telemetry.record", None),
    ("wisent-errors.telemetry.store", None),
    ("wisent-errors.telemetry.deliver", None),
    ("wisent-errors.telemetry.export", Some("it writes a file the user names, so only `telemetry export` writes one")),
    ("wisent_errors.envelope.build", Some("it builds the envelope of a failure a product reports, so only `telemetry failure` builds one")),
    ("wisent-errors.support.report", Some("it files a report a person at support reads, so only `support report` files one")),
    ("wisent-errors.support.status", None),
    ("wisent-errors.support.exchange", None),
    ("wisent_errors.command.check", Some("it reads the files a product's CI names, so only `doctor check` and `warnings check` read them")),
    ("wisent_errors.cli_output.diagnose", Some("it is this diagnosis, which says a probe that fails without saying why in that probe's own line")),
    ("wisent_errors.cli_output.print", Some("the diagnosis is printed through it, so a standard output it cannot write is this command's own refusal")),
];

/// What one tried functionality was found to be.
enum Found {
    Works(String),
    /// Its failure point, detail and remedy; every failure here is `config`.
    Fails(&'static str, String, String),
}

/// The finding of each functionality the doctor tries.
type Tried = [(&'static str, Found); 7];

fn found<'a>(tried: &'a Tried, id: &str) -> &'a Found {
    match tried.iter().find(|(name, _)| *name == id) {
        Some((_, found)) => found,
        None => panic!("the case names no finding for {id}"),
    }
}

/// The doctor's lines, as it prints them without `--json`.
fn lines(tried: &Tried) -> String {
    let said: Vec<String> = SAID
        .iter()
        .map(|(id, skipped)| match skipped {
            Some(why) => format!("skipped {id}: {why}"),
            None => match found(tried, id) {
                Found::Works(observed) => format!("ok      {id}: {observed}"),
                Found::Fails(_, detail, remedy) => format!("failed  {id}: {detail}; fix: {remedy}"),
            },
        })
        .collect();
    format!("{}\n", said.join("\n"))
}

/// The doctor's findings, as `--json` prints them.
fn findings(tried: &Tried) -> Value {
    Value::Array(
        SAID.iter()
            .map(|(id, skipped)| match skipped {
                Some(why) => json!({ "operation": id, "state": "skipped", "why": why }),
                None => match found(tried, id) {
                    Found::Works(observed) => json!({ "operation": id, "state": "works", "observed": observed }),
                    Found::Fails(point, detail, remedy) => json!({ "operation": id, "state": "fails", "failure_point": point, "error_code": "config", "detail": detail, "remedy": remedy }),
                },
            })
            .collect(),
    )
}

const PUBLIC_COLLECTOR: &str = "events go to https://telemetry.wisent.com/api/analytics/mobile/collect, named by wisent-errors";
const PUBLIC_SUPPORT: &str = "reports go to https://support.wisent.com/v1/public/reports, named by wisent-errors";

#[test]
fn doctor_tries_every_functionality_and_says_what_failed_and_its_fix() {
    let mut case = Case::new("doctor");
    let state = case.home.join("telemetry");
    let product = format!("{} names {PRODUCT} 1.0.0, app example-product-cli", case.product.display());
    let works = |observed: &str| Found::Works(observed.to_owned());

    // Everything works on a machine where nothing was answered yet.
    let working: Tried = [
        ("wisent_errors.command.product", works(&product)),
        ("wisent-errors.telemetry.consent", works("the user has not answered, so nothing is queued or sent")),
        ("wisent-errors.telemetry.record", works("0 event(s) wait to be sent")),
        ("wisent-errors.telemetry.store", works("~/telemetry can be written")),
        ("wisent-errors.telemetry.deliver", works(PUBLIC_COLLECTOR)),
        ("wisent-errors.support.status", works("no report was filed from this installation")),
        ("wisent-errors.support.exchange", works(PUBLIC_SUPPORT)),
    ];
    let (status, stdout, stderr) = case.run(&["doctor"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{stdout}");
    assert_eq!(stdout, lines(&working));
    let left: Vec<_> = std::fs::read_dir(&state).expect("the probe made the telemetry directory").collect();
    assert!(left.is_empty(), "the probe removed its file: {left:?}");

    // A consent file holding no level, and a collector and a support
    // address the product refuses: each fails with what failed and its fix.
    let consent = state.join("consent.json");
    let damaged = r#"{"level":"sometimes"}"#;
    std::fs::write(&consent, damaged).expect("the consent file");
    let (collector, support) = ("http://collector.example.invalid/api/analytics/mobile/collect", "http://support.example.invalid/v1/public/reports");
    case.set("WISENT_TELEMETRY_COLLECTOR_URL", collector);
    case.set("WISENT_SUPPORT_URL", support);
    let unset: Tried = [
        ("wisent_errors.command.product", works(&product)),
        (
            "wisent-errors.telemetry.consent",
            Found::Fails(
                "wisent-errors.telemetry.consent",
                format!("reading the telemetry consent from {path}: the file is not what telemetry wrote: level \"sometimes\" is not off, errors or usage; observed: the file holds {} bytes", damaged.len(), path = consent.display()),
                format!("answer again, in an app's settings or with `{PRODUCT} telemetry on|off`, which rewrites it, or remove {}", consent.display()),
            ),
        ),
        ("wisent-errors.telemetry.record", works("0 event(s) wait to be sent")),
        ("wisent-errors.telemetry.store", works("~/telemetry can be written")),
        (
            "wisent-errors.telemetry.deliver",
            Found::Fails(
                "wisent-errors.telemetry.deliver",
                format!("reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds {collector}"),
                "set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it".to_owned(),
            ),
        ),
        ("wisent-errors.support.status", works("no report was filed from this installation")),
        (
            "wisent-errors.support.exchange",
            Found::Fails(
                "wisent-errors.support.report",
                format!("reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds {support}"),
                "set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it".to_owned(),
            ),
        ),
    ];
    let (status, stdout, stderr) = case.run(&["doctor"]);
    assert_eq!((status, stderr.as_str()), (FAILURE, ""), "{stdout}");
    assert_eq!(stdout, lines(&unset));
    assert_eq!(std::fs::read_to_string(&consent).expect("the consent file"), damaged, "the doctor leaves the file as it was");

    // The same findings as JSON.
    let (status, stdout, stderr) = case.run(&["doctor", "--json"]);
    assert_eq!((status, stderr.as_str()), (FAILURE, ""), "{stdout}");
    assert_eq!(serde_json::from_str::<Value>(&stdout).expect("the doctor prints JSON"), findings(&unset));

    // A telemetry directory below a file: every functionality that keeps
    // or reads a file there fails naming it; nothing is made under the file.
    case.unset("WISENT_TELEMETRY_COLLECTOR_URL");
    case.unset("WISENT_SUPPORT_URL");
    let blocker = case.root.join("a-file");
    std::fs::write(&blocker, "not a directory").expect("the blocking file");
    let home = blocker.join("telemetry");
    case.set("WISENT_TELEMETRY_HOME", &home.display().to_string());
    let (consent, queue, probe, reports) = (home.join("consent.json"), home.join("queue"), home.join("doctor-probe.json"), home.join("support"));
    let denied = std::fs::read(&consent).expect_err("nothing is read below a file").to_string();
    let examined = std::fs::metadata(&consent).expect_err("nothing is below a file").to_string();
    let listed = std::fs::read_dir(&queue).expect_err("nothing is listed below a file").to_string();
    let made = std::fs::create_dir_all(&home).expect_err("no directory is made below a file").to_string();
    let unwritable = |what: &str, path: &Path, why: &str| {
        Found::Fails(
            "wisent-errors.telemetry.record",
            format!("keeping {what} in {}: the telemetry directory could not be written: {why}; observed: directory {}", path.display(), home.display()),
            format!("make {} writable by this user, or name a writable one with WISENT_TELEMETRY_HOME", home.display()),
        )
    };
    let below_a_file: Tried = [
        ("wisent_errors.command.product", works(&product)),
        (
            "wisent-errors.telemetry.consent",
            Found::Fails(
                "wisent-errors.telemetry.record",
                format!("reading the telemetry consent from {path}: the operating system refused the read, so what the file holds was never looked at; observed: {path} cannot be examined either: {examined}; the operating system answered {denied}", path = consent.display()),
                format!("let the user running {PRODUCT} read it (chmod u+r {path}), or remove {path} so telemetry writes it again", path = consent.display()),
            ),
        ),
        ("wisent-errors.telemetry.record", unwritable("the event queue", queue.as_path(), &listed)),
        ("wisent-errors.telemetry.store", unwritable("the doctor's probe", probe.as_path(), &made)),
        ("wisent-errors.telemetry.deliver", works(PUBLIC_COLLECTOR)),
        ("wisent-errors.support.status", unwritable("the support reports", reports.as_path(), &listed)),
        ("wisent-errors.support.exchange", works(PUBLIC_SUPPORT)),
    ];
    let (status, stdout, stderr) = case.run(&["doctor", "--json"]);
    assert_eq!((status, stderr.as_str()), (FAILURE, ""), "{stdout}");
    assert_eq!(serde_json::from_str::<Value>(&stdout).expect("the doctor prints JSON"), findings(&below_a_file));
    assert_eq!(std::fs::read_to_string(&blocker).expect("the blocking file"), "not a directory", "nothing was made under the file");

    // An operand the doctor does not take.
    let (status, stdout, stderr) = case.run(&["doctor", "now"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the operands of `wisent-errors doctor`: the command takes no operand, and \"now\" is more than it reads; observed: its operands were [\"now\"]",
            "drop \"now\", or quote an operand that holds spaces as one word, as in `wisent-errors --product <file> doctor [--json]`",
            "wisent_errors.command.arguments", "operand-extra", "command",
        )
    );
}

/// `doctor check` passing the doctor's own findings against its own
/// catalogue, then without its second file, with a file that is not there,
/// with files that are not what their commands print, and with findings
/// that miss a functionality, try one twice and try one the catalogue does
/// not declare.
#[test]
fn doctor_check_holds_the_findings_to_the_errors_list() {
    let case = Case::new("doctor-check");

    // What the product's CI holds to each other: its own listing and findings.
    let (status, listing, stderr) = case.bare(&["errors", "list"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{listing}");
    let catalogue: Value = serde_json::from_str(&listing).expect("the listing is JSON");
    let ids: Vec<&str> = catalogue.as_array().expect("a list").iter().map(|operation| operation["operation"].as_str().expect("an id")).collect();
    assert_eq!(
        ids,
        [
            "wisent_errors.command.arguments",
            "wisent_errors.command.product",
            "wisent_errors.command.check",
            "wisent_errors.cli_output.read_json",
            "wisent_errors.cli_output.print",
            "wisent_errors.cli_output.diagnose",
            "wisent_errors.envelope.build",
            "wisent-errors.telemetry.record",
            "wisent-errors.telemetry.consent",
            "wisent-errors.telemetry.deliver",
            "wisent-errors.support.report",
            "wisent-errors.support.status",
            "wisent-errors.telemetry.export",
            "wisent-errors.telemetry.store",
            "wisent-errors.support.exchange",
        ]
    );
    assert_eq!(
        catalogue[2]["entries"],
        json!(["wisent-errors doctor check <errors-list.json> <doctor.json>", "wisent-errors warnings check <warnings-list.json>"])
    );
    let started = catalogue.as_array().expect("a list").iter().filter(|operation| operation["entries"] != json!([])).count();
    assert_eq!(started, 13, "every functionality but the store and the support exchange has an entry point");
    case.write("errors.json", &listing);
    let (status, doctor, stderr) = case.run(&["doctor", "--json"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{doctor}");
    case.write("doctor.json", &doctor);

    let (status, stdout, stderr) = case.bare(&["doctor", "check", "errors.json", "doctor.json"]);
    assert_eq!((status, stderr.as_str()), (SUCCESS, ""), "{stdout}");
    assert_eq!(serde_json::from_str::<Value>(&stdout).expect("JSON"), json!({ "functionalities": 15, "with_entry_points": 13, "findings": 15 }));
    assert_eq!((case.read("errors.json"), case.read("doctor.json")), (listing.clone(), doctor.clone()), "the check leaves both files as they were");

    // Without the findings.
    let (status, stdout, stderr) = case.bare(&["doctor", "check", "errors.json"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the operands of `wisent-errors doctor check`: the command takes the failure catalogue `<product> errors list --json` printed and the findings `<product> doctor --json` printed and was given 1; observed: its operands were [\"errors.json\"]",
            "give the failure catalogue `<product> errors list --json` printed and the findings `<product> doctor --json` printed, as in `wisent-errors doctor check <errors-list.json> <doctor.json>`",
            "wisent_errors.command.arguments", "operand-missing", "command",
        )
    );

    // Findings that are not there: the reader of JSON inputs refuses them.
    let absent = case.root.join("absent.json");
    let missing = std::fs::metadata(&absent).expect_err("nothing is there").to_string();
    let answered = std::fs::read(&absent).expect_err("nothing is there").to_string();
    let entries = std::fs::read_dir(&case.root).expect("the case directory").count();
    let (status, stdout, stderr) = case.bare(&["doctor", "check", "errors.json", "absent.json"]);
    assert_eq!((status, stdout.as_str()), (USAGE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            &format!("reading the JSON input absent.json: no file is at that path; observed: absent.json cannot be examined ({missing}); . exists and holds {entries} entries; the operating system answered {answered}"),
            &format!("name a file that exists, or write it first; a relative path is read from {}", case.root.display()),
            "wisent_errors.cli_output.read_json", "input-absent", "cli-output",
        )
    );

    // Findings that are not the list `doctor --json` prints.
    case.write("summary.json", r#"{"findings": []}"#);
    let (status, stdout, stderr) = case.bare(&["doctor", "check", "errors.json", "summary.json"]);
    assert_eq!((status, stdout.as_str()), (FAILURE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the doctor's findings summary.json: the document is not the list of findings `doctor --json` prints; observed: the document holds the object {\"findings\":[]}",
            "name the file `<product> doctor --json` printed, or print it again with `<product> doctor --json`",
            "wisent_errors.command.check", "input-shape-invalid", "command",
        )
    );
    assert_eq!(case.read("summary.json"), r#"{"findings": []}"#);

    // A listing whose functionality names its entry as one text.
    let mut broken = catalogue.clone();
    broken[2]["entries"] = json!("wisent-errors doctor check");
    let broken = broken.to_string();
    case.write("broken.json", &broken);
    let (status, stdout, stderr) = case.bare(&["doctor", "check", "broken.json", "doctor.json"]);
    assert_eq!((status, stdout.as_str()), (FAILURE, ""), "{stderr}");
    assert_eq!(
        stderr,
        refusal(
            "reading the failure catalogue broken.json: functionality 3 (wisent_errors.command.check)'s \"entries\" is not a list of the texts that start it; observed: functionality 3 (wisent_errors.command.check)'s \"entries\" holds the text \"wisent-errors doctor check\"",
            "name the file `<product> errors list --json` printed, or print it again with `<product> errors list --json`",
            "wisent_errors.command.check", "input-shape-invalid", "command",
        )
    );
    assert_eq!(case.read("broken.json"), broken);

    // Findings that miss the export, try consent twice and try a
    // functionality the catalogue does not declare.
    let mut incomplete: Vec<Value> = serde_json::from_str::<Value>(&doctor).expect("the findings").as_array().expect("a list").clone();
    incomplete.retain(|finding| finding["operation"] != "wisent-errors.telemetry.export");
    let Some(consent) = incomplete.iter().find(|finding| finding["operation"] == "wisent-errors.telemetry.consent").cloned() else {
        panic!("the doctor reports consent: {doctor}");
    };
    incomplete.push(consent);
    incomplete.push(json!({ "operation": "example-product.undeclared", "state": "skipped", "why": "it is not declared" }));
    let incomplete = Value::Array(incomplete).to_string();
    case.write("incomplete.json", &incomplete);
    let (status, stdout, stderr) = case.bare(&["doctor", "check", "errors.json", "incomplete.json"]);
    assert_eq!((status, stdout.as_str()), (FAILURE, ""), "{stderr}");
    let problems = [
        "(1) wisent-errors.telemetry.consent is checked 2 times, so the diagnosis would try it more than once and print each answer: keep one Check for it, a Probe::Run or a Probe::Skipped, and drop the others".to_owned(),
        "(2) wisent-errors.telemetry.export has an entry point and no diagnosis check: give it a Probe::Run, or a Probe::Skipped saying why it is not tried".to_owned(),
        format!("(3) example-product.undeclared is checked but the catalogue does not declare it; the catalogue declares {}: declare it in the catalogue, or drop its Check", ids.join(", ")),
    ];
    assert_eq!(
        stderr,
        refusal(
            &format!("holding the doctor's findings in incomplete.json to the functionalities errors.json declares: 3 problem(s) keep the doctor from trying each functionality once: {}; observed: 13 functionality(ies) with an entry point declared, 16 finding(s) reported", problems.join(" ")),
            "give every functionality with an entry point one diagnosis check, a probe or a skip saying why, drop a second check and every check of a functionality the catalogue does not declare, then print the findings again with `<product> doctor --json`",
            "wisent_errors.command.check", "doctor-incomplete", "command",
        )
    );
    assert_eq!((case.read("errors.json"), case.read("incomplete.json")), (listing, incomplete), "a refused check leaves both files as they were");
}
