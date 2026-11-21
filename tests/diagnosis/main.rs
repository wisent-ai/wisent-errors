//! The diagnosis a product's `doctor` prints: its checks are held to the
//! catalogue, and each functionality is tried for real on this machine.
//! The probes here read a file that is there and one that is not, in a
//! directory of the run's own under the checkout's build directory.

use std::path::PathBuf;
use std::sync::LazyLock;

use wisent_errors::diagnosis::{self, Check, Probe};
use wisent_errors::{Code, Failure, Operation};

/// A diagnosis where everything works, EXIT_SUCCESS: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const SUCCESS: i32 = 0;
/// A diagnosis where something fails, EXIT_FAILURE: https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const FAILURE: i32 = 1;

const fn operation(id: &'static str, entries: &'static [&'static str]) -> Operation {
    Operation {
        id,
        entries,
        uses: &[],
        summary: "a functionality of the diagnosis test",
        docs: "https://github.com/wisent-ai/wisent-errors/blob/main/docs/diagnosis.md",
        causes: &[],
        warnings: &[],
    }
}

static READ: Operation = operation("diagnosis-test.read", &["diagnosis-test read"]);
static MISSING: Operation = operation("diagnosis-test.missing", &["diagnosis-test missing"]);
static REMOVE: Operation = operation("diagnosis-test.remove", &["diagnosis-test remove"]);
static INTERNAL: Operation = operation("diagnosis-test.internal", &[]);
static UNDECLARED: Operation =
    operation("diagnosis-test.undeclared", &["diagnosis-test undeclared"]);
static SILENT: Operation = operation("diagnosis-test.silent", &["diagnosis-test silent"]);
static HALF: Operation = operation("diagnosis-test.half", &["diagnosis-test half"]);

static CATALOGUE: &[&Operation] = &[&READ, &MISSING, &REMOVE, &INTERNAL];

/// The run's own directory, holding `present.txt` and no `absent.txt`.
static ROOT: LazyLock<PathBuf> = LazyLock::new(|| {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../.build/diagnosis")
        .join(std::process::id().to_string());
    std::fs::create_dir_all(&root).expect("the run's directory");
    std::fs::write(root.join("present.txt"), "here").expect("the present file");
    root
});

fn read(name: &str) -> Result<String, Failure> {
    let path = ROOT.join(name);
    std::fs::read_to_string(&path)
        .map(|text| format!("{} holds {} bytes", path.display(), text.len()))
        .map_err(|error| {
            Failure::new("diagnosis-test.read", Code::NotFound, "diagnosis-test")
                .expect("a valid failure point")
                .detail(format!("reading {}: {error}", path.display()))
                .remedy(format!("put the file back at {}", path.display()))
        })
}

fn checks() -> Vec<Check> {
    vec![
        Check {
            operation: &READ,
            probe: Probe::Run(|| read("present.txt")),
        },
        Check {
            operation: &MISSING,
            probe: Probe::Run(|| read("absent.txt")),
        },
        Check {
            operation: &REMOVE,
            probe: Probe::Skipped("it deletes the user's data"),
        },
    ]
}

#[test]
fn every_functionality_is_tried_and_a_failure_says_what_failed_and_its_fix() {
    let findings = diagnosis::diagnose(&checks());
    let present = ROOT.join("present.txt");
    let absent = ROOT.join("absent.txt");
    let os = std::fs::read_to_string(&absent).expect_err("absent.txt is not there").to_string();
    assert_eq!(
        diagnosis::render(&findings),
        format!(
            "ok      diagnosis-test.read: {present} holds 4 bytes\n\
             failed  diagnosis-test.missing: reading {absent}: {os}; fix: put the file back at {absent}\n\
             skipped diagnosis-test.remove: it deletes the user's data",
            present = present.display(),
            absent = absent.display()
        )
    );
    assert_eq!(
        diagnosis::exit_status(&findings),
        FAILURE,
        "a failing functionality fails the diagnosis"
    );
    assert_eq!(
        diagnosis::to_json(&findings),
        serde_json::json!([
            {"operation": "diagnosis-test.read", "state": "works", "observed": format!("{} holds 4 bytes", present.display())},
            {
                "operation": "diagnosis-test.missing",
                "state": "fails",
                "failure_point": "diagnosis-test.read",
                "error_code": "not_found",
                "detail": format!("reading {}: {os}", absent.display()),
                "remedy": format!("put the file back at {}", absent.display()),
            },
            {"operation": "diagnosis-test.remove", "state": "skipped", "why": "it deletes the user's data"},
        ])
    );
}

#[test]
fn a_diagnosis_where_everything_works_passes() {
    let findings = diagnosis::diagnose(&[Check {
        operation: &READ,
        probe: Probe::Run(|| read("present.txt")),
    }]);
    assert_eq!(
        diagnosis::exit_status(&findings),
        SUCCESS,
        "{}",
        diagnosis::render(&findings)
    );
    assert_eq!(
        diagnosis::render(&findings),
        format!("ok      diagnosis-test.read: {} holds 4 bytes", ROOT.join("present.txt").display())
    );
}

#[test]
fn the_checks_are_held_to_the_catalogue() {
    assert_eq!(
        diagnosis::problems(CATALOGUE, &checks()),
        Vec::<String>::new(),
        "every declared entry point has one check"
    );
    let mut short = checks();
    short.pop();
    assert_eq!(
        diagnosis::problems(CATALOGUE, &short),
        vec!["diagnosis-test.remove has an entry point and no diagnosis check: give it a Probe::Run, or a Probe::Skipped saying why it is not tried".to_owned()]
    );
    let mut twice = checks();
    twice.push(Check {
        operation: &READ,
        probe: Probe::Skipped("again"),
    });
    twice.push(Check {
        operation: &UNDECLARED,
        probe: Probe::Skipped("not in the catalogue"),
    });
    assert_eq!(
        diagnosis::problems(CATALOGUE, &twice),
        vec![
            "diagnosis-test.read is checked 2 times, so the diagnosis would try it more than once and print each answer: keep one Check for it, a Probe::Run or a Probe::Skipped, and drop the others".to_owned(),
            "diagnosis-test.undeclared is checked but the catalogue does not declare it; the catalogue declares diagnosis-test.read, diagnosis-test.missing, diagnosis-test.remove, diagnosis-test.internal: declare it in the catalogue, or drop its Check".to_owned(),
        ]
    );
}

/// A probe whose failure says neither what failed nor what fixes it, the
/// way a hand-built envelope does, and one that says only what failed.
fn silent() -> Result<String, Failure> {
    Err(Failure::new("diagnosis-test.silent", Code::InfraDown, "diagnosis-test").expect("a valid failure point"))
}

fn half() -> Result<String, Failure> {
    Err(Failure::new("diagnosis-test.half", Code::NotFound, "diagnosis-test")
        .expect("a valid failure point")
        .detail("reading example-host's registry: no key fleet/example-host"))
}

#[test]
fn a_probe_failing_without_saying_why_is_refused() {
    let findings = diagnosis::diagnose(&[
        Check { operation: &SILENT, probe: Probe::Run(silent) },
        Check { operation: &HALF, probe: Probe::Run(half) },
    ]);
    let refusal = |operation: &str, missing: &str, point: &str, code: &str| {
        (
            format!("trying {operation} for the diagnosis: its probe failed with an envelope that carries {missing}, so the diagnosis could not say what failed or what fixes it; observed: failure_point {point}, code {code}"),
            format!("raise the probe's failure from a declared cause of {operation}, which carries its detail and its remedy"),
        )
    };
    let (silent_detail, silent_remedy) = refusal("diagnosis-test.silent", "neither a detail nor a remedy", "diagnosis-test.silent", "infra_down");
    let (half_detail, half_remedy) = refusal("diagnosis-test.half", "no remedy", "diagnosis-test.half", "not_found");
    assert_eq!(
        diagnosis::render(&findings),
        format!("failed  diagnosis-test.silent: {silent_detail}; fix: {silent_remedy}\nfailed  diagnosis-test.half: {half_detail}; fix: {half_remedy}")
    );
    assert_eq!(diagnosis::exit_status(&findings), FAILURE);
    assert_eq!(
        diagnosis::to_json(&findings),
        serde_json::json!([
            {"operation": "diagnosis-test.silent", "state": "fails", "failure_point": "wisent_errors.cli_output.diagnose", "error_code": "config", "detail": silent_detail, "remedy": silent_remedy},
            {"operation": "diagnosis-test.half", "state": "fails", "failure_point": "wisent_errors.cli_output.diagnose", "error_code": "config", "detail": half_detail, "remedy": half_remedy},
        ])
    );
}
