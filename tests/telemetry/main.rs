//! Telemetry against the real Echo app collector named by
//! `WISENT_TELEMETRY_TEST_COLLECTOR`. Each case runs in its own directory
//! under the package's build directory, with its own `WISENT_TELEMETRY_HOME`,
//! and removes it when done. Environment variables are the process's, so the
//! cases take one lock and run one at a time.
//!
//! Every run appends what it did to `.build/telemetry/<run>/report.json` at the
//! repository root: the source revision, the collector, and each case's
//! attempts and final store.

mod consent;
mod delivery;
mod events;
mod signals;
mod store;
mod support;

use std::path::PathBuf;
use std::sync::{LazyLock, Mutex, MutexGuard};

use serde_json::{json, Value};
use wisent_errors::telemetry::{Product, Telemetry};
use wisent_errors::{Code, Failure};

static LOCK: Mutex<()> = Mutex::new(());

pub struct Case {
    pub root: PathBuf,
    name: &'static str,
    notes: Vec<Value>,
    _lock: MutexGuard<'static, ()>,
}

impl Case {
    pub fn new(name: &'static str) -> Self {
        let lock = LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
            .join("telemetry")
            .join(format!("{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("the case directory");
        for variable in [
            "WISENT_TELEMETRY_COLLECTOR_URL",
            "WISENT_SUPPORT_URL",
            "DO_NOT_TRACK",
            "XDG_STATE_HOME",
        ] {
            std::env::remove_var(variable);
        }
        std::env::set_var("WISENT_TELEMETRY_HOME", root.join("state"));
        Self {
            root,
            name,
            notes: Vec::new(),
            _lock: lock,
        }
    }

    pub fn telemetry(&self, app_id: &'static str) -> Telemetry {
        Telemetry::new(Product {
            id: "wisent-errors-test",
            app_id,
            version: env!("CARGO_PKG_VERSION"),
        })
    }

    pub fn note(&mut self, what: &str, value: Value) {
        self.notes.push(json!({ "what": what, "value": value }));
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let state = std::fs::read_dir(self.root.join("state").join("queue"))
            .map(|entries| entries.count())
            .unwrap_or(0);
        let delivery = std::fs::read_to_string(self.root.join("state").join("delivery.json")).ok();
        record(json!({
            "case": self.name,
            "passed": !std::thread::panicking(),
            "notes": self.notes,
            "queued_at_end": state,
            "delivery_at_end": delivery,
        }));
        let _ = std::fs::remove_dir_all(&self.root);
        std::env::remove_var("WISENT_TELEMETRY_HOME");
    }
}

/// The real collector the delivery cases send to.
pub fn collector() -> String {
    std::env::var("WISENT_TELEMETRY_TEST_COLLECTOR").expect(
        "set WISENT_TELEMETRY_TEST_COLLECTOR to the Echo app collector, \
         https://<echo web>/api/analytics/mobile/collect: these cases run against the real one",
    )
}

/// A failure the way a product raises one, with a home path and this
/// machine's host name in its detail.
pub fn sample_failure() -> Failure {
    let home = std::env::var("HOME").unwrap_or_default();
    Failure::new(
        "wisent-errors-test.pairs.import",
        Code::NotFound,
        "wisent-errors-test",
    )
    .expect("a valid failure point")
    .detail(format!("reading {home}/pairs/calm.json: no such file"))
    .remedy(format!("write {home}/pairs/calm.json first"))
}

fn record(entry: Value) {
    static RUN: LazyLock<PathBuf> = LazyLock::new(|| {
        let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..");
        let revision = std::process::Command::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(&repository)
            .output()
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
            .unwrap_or_default();
        let dirty = std::process::Command::new("git")
            .args(["status", "--porcelain"])
            .current_dir(&repository)
            .output()
            .map(|output| !output.stdout.is_empty())
            .unwrap_or(true);
        let run = repository.join(".build").join("telemetry").join(format!(
            "{}-{}",
            revision.get(..12).unwrap_or("unknown"),
            std::process::id()
        ));
        std::fs::create_dir_all(&run).expect("the run directory");
        let report = run.join("report.json");
        let header = json!({
            "revision": revision,
            "dirty": dirty,
            "collector": std::env::var("WISENT_TELEMETRY_TEST_COLLECTOR").ok(),
            "app_id": std::env::var("WISENT_TELEMETRY_TEST_APP_ID").ok(),
            "cases": [],
        });
        std::fs::write(&report, header.to_string()).expect("the report");
        report
    });
    let file: &PathBuf = &RUN;
    let mut report: Value = std::fs::read_to_string(file)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_else(|| json!({ "cases": [] }));
    if let Some(cases) = report["cases"].as_array_mut() {
        cases.push(entry);
    }
    let _ = std::fs::write(
        file,
        serde_json::to_string_pretty(&report).unwrap_or_default(),
    );
}
