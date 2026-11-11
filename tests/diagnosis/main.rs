//! The diagnosis a product's `doctor` prints: its checks are held to the
//! catalogue, and each functionality is tried for real on this machine.
//! The probes here read a file that is there and one that is not, in a
//! directory of the run's own under the checkout's build directory.

use std::path::PathBuf;
use std::sync::LazyLock;

use wisent_errors::diagnosis::{self, Check, Probe};
use wisent_errors::{Code, Failure, Operation};

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
    let lines = diagnosis::render(&findings);
    let present = ROOT.join("present.txt");
    let absent = ROOT.join("absent.txt");
    assert!(
        lines.contains(&format!(
            "ok      diagnosis-test.read: {} holds 4 bytes",
            present.display()
        )),
        "{lines}"
    );
    assert!(
        lines.contains(&format!(
            "failed  diagnosis-test.missing: reading {}: ",
            absent.display()
        )),
        "{lines}"
    );
    assert!(
        lines.contains(&format!("fix: put the file back at {}", absent.display())),
        "{lines}"
    );
    assert!(
        lines.contains("skipped diagnosis-test.remove: it deletes the user's data"),
        "{lines}"
    );
    assert_eq!(
        diagnosis::exit_status(&findings),
        1,
        "a failing functionality fails the diagnosis"
    );
    let json = diagnosis::to_json(&findings);
    assert_eq!(json[1]["state"], "fails");
    assert_eq!(json[1]["error_code"], "not_found");
    assert_eq!(json[2]["state"], "skipped");
}

#[test]
fn a_diagnosis_where_everything_works_passes() {
    let findings = diagnosis::diagnose(&[Check {
        operation: &READ,
        probe: Probe::Run(|| read("present.txt")),
    }]);
    assert_eq!(
        diagnosis::exit_status(&findings),
        0,
        "{}",
        diagnosis::render(&findings)
    );
}

#[test]
fn the_checks_are_held_to_the_catalogue() {
    assert!(
        diagnosis::problems(CATALOGUE, &checks()).is_empty(),
        "every declared entry point has one check"
    );
    let mut short = checks();
    short.pop();
    let problems = diagnosis::problems(CATALOGUE, &short);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems[0].starts_with("diagnosis-test.remove has an entry point and no diagnosis check"),
        "{problems:?}"
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
    let problems = diagnosis::problems(CATALOGUE, &twice);
    assert!(
        problems.contains(&"diagnosis-test.read is checked 2 times".to_string()),
        "{problems:?}"
    );
    assert!(
        problems.contains(
            &"diagnosis-test.undeclared is checked but the catalogue does not declare it"
                .to_string()
        ),
        "{problems:?}"
    );
}
