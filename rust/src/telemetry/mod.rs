//! Telemetry from installed copies: what failed on a user's machine, and with
//! a wider consent which commands ran, sent to Echo's app collector. The
//! contract, every file it keeps and every sentence it says are in
//! docs/telemetry.md.
//!
//! Two rules carry it. Nothing is queued before the user answers, and nothing
//! here ever changes the product's own result: every failure of telemetry is
//! said once on stderr, starting with `wisent-errors:`, and the product goes on.

// Every refusal here is the crate's own envelope, the value a product prints
// and reports; boxing it would give telemetry a second failure type.
#![allow(clippy::result_large_err)]

mod causes;
mod deliver;
pub mod events;
mod signals;
mod store;
mod support;

use std::io::{BufRead, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use serde_json::{json, Map, Value};

/// The functionalities a product's own `telemetry` and `support` commands
/// use, for its catalogue's `uses`.
pub use causes::{operations, CONSENT, DELIVER, RECORD, REPORT, STATUS};
pub use deliver::Delivered;
pub use events::{Event, EVENTS};
pub use support::{Report, PUBLIC_SUPPORT};

use crate::Failure;
use store::Cleaner;

/// Which product is reporting.
#[derive(Clone, Copy, Debug)]
pub struct Product {
    pub id: &'static str,
    /// The app id the collector declares for this surface of the product:
    /// `ster-cli`, `ster-desktop`.
    pub app_id: &'static str,
    pub version: &'static str,
}

/// What the user agreed to send.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Off,
    Errors,
    Usage,
}

impl Level {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Errors => "errors",
            Self::Usage => "usage",
        }
    }

    /// `off`, `errors` or `usage`, or the refusal naming them.
    pub fn parse(text: &str, product: &str) -> Result<Self, Failure> {
        match text.trim() {
            "off" => Ok(Self::Off),
            "errors" => Ok(Self::Errors),
            "usage" => Ok(Self::Usage),
            other => {
                Err(causes::LEVEL_UNKNOWN.failure(CONSENT_POINT, product, &[("level", other)]))
            }
        }
    }
}

/// Where events are sent, and what named the address.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Collector {
    pub url: String,
    /// `WISENT_TELEMETRY_COLLECTOR_URL`, or `wisent-errors` for the public
    /// collector address every product is built with.
    pub source: &'static str,
}

/// The public address Wisent's collector answers telemetry on. Every product
/// sends here unless `WISENT_TELEMETRY_COLLECTOR_URL` names another collector,
/// such as a self-hosted Echo or a test's.
pub const PUBLIC_COLLECTOR: &str = "https://telemetry.wisent.com/api/analytics/mobile/collect";

const CONSENT_POINT: &str = "wisent-errors.telemetry.consent";
const RUNTIME_COLLECTOR: &str = "WISENT_TELEMETRY_COLLECTOR_URL";

pub struct Telemetry {
    product: Product,
    directory: Option<PathBuf>,
    session: Option<String>,
    cleaner: Cleaner,
}

impl Telemetry {
    pub fn new(product: Product) -> Self {
        Self {
            directory: store::directory(product.id),
            session: store::random_id(),
            cleaner: Cleaner::of_this_machine(),
            product,
        }
    }

    pub fn product(&self) -> &Product {
        &self.product
    }

    /// The directory this product's telemetry lives in.
    pub fn directory(&self) -> Option<&Path> {
        self.directory.as_deref()
    }

    fn file(&self, name: &str) -> Option<PathBuf> {
        self.directory
            .as_ref()
            .map(|directory| directory.join(name))
    }

    fn queue_directory(&self) -> Option<PathBuf> {
        self.file("queue")
    }

    /// `DO_NOT_TRACK` set to `1` or `true` turns every level off.
    pub fn do_not_track() -> bool {
        std::env::var("DO_NOT_TRACK")
            .map(|value| matches!(value.trim(), "1" | "true"))
            .unwrap_or(false)
    }

    /// The level the user chose, `None` while unanswered.
    pub fn level(&self) -> Result<Option<Level>, Failure> {
        let Some(path) = self.file("consent.json") else {
            return Ok(None);
        };
        let Some(consent) = store::read_json(
            &path,
            "the telemetry consent",
            self.product.id,
            self.product.id,
        )?
        else {
            return Ok(None);
        };
        let level = consent.get("level").and_then(Value::as_str).unwrap_or("");
        Level::parse(level, self.product.id).map(Some).map_err(|_| {
            causes::FILE_UNREADABLE.failure(
                CONSENT_POINT,
                self.product.id,
                &[
                    ("what", "the telemetry consent"),
                    ("path", &path.display().to_string()),
                    (
                        "error",
                        &format!("level {level:?} is not off, errors or usage"),
                    ),
                    ("bytes", &consent.to_string().len().to_string()),
                    ("product", self.product.id),
                ],
            )
        })
    }

    /// Keep the user's answer. Turning telemetry off also drops every event
    /// still waiting, since the user no longer agrees to send them.
    pub fn set_level(&self, level: Level) -> Result<(), Failure> {
        let path = self
            .file("consent.json")
            .ok_or_else(|| self.no_home("the telemetry consent"))?;
        store::write_json(
            &path,
            "the telemetry consent",
            &json!({ "level": level.as_str(), "answered_at": store::now() }),
            self.product.id,
        )?;
        if level == Level::Off {
            if let Some(queue) = self.queue_directory() {
                if let Err(error) = std::fs::remove_dir_all(&queue) {
                    if error.kind() != std::io::ErrorKind::NotFound {
                        return Err(self.unwritable("the event queue", &queue, &error));
                    }
                }
            }
        }
        Ok(())
    }

    /// What is actually sent: nothing while unanswered or under `DO_NOT_TRACK`.
    fn effective(&self) -> Result<Level, Failure> {
        if Self::do_not_track() {
            return Ok(Level::Off);
        }
        Ok(self.level()?.unwrap_or(Level::Off))
    }

    /// The collector address and what named it, or the refusal of one that
    /// is not https:// (or http:// on a loopback host).
    pub fn collector(&self) -> Result<Collector, Failure> {
        let runtime = std::env::var(RUNTIME_COLLECTOR)
            .ok()
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let Some(address) = runtime else {
            return Ok(Collector {
                url: PUBLIC_COLLECTOR.to_owned(),
                source: "wisent-errors",
            });
        };
        if acceptable_collector(&address) {
            Ok(Collector {
                url: address,
                source: RUNTIME_COLLECTOR,
            })
        } else {
            Err(causes::COLLECTOR_INVALID.failure(
                DELIVER_POINT,
                self.product.id,
                &[("source", RUNTIME_COLLECTOR), ("address", &address)],
            ))
        }
    }

    /// This installation's random id, made on first use.
    fn installation(&self) -> Result<String, Failure> {
        let path = self
            .file("installation.json")
            .ok_or_else(|| self.no_home("the installation id"))?;
        if let Some(existing) = store::read_json(
            &path,
            "the installation id",
            self.product.id,
            self.product.id,
        )? {
            if let Some(id) = existing.get("id").and_then(Value::as_str) {
                return Ok(id.to_owned());
            }
        }
        let id = store::random_id().ok_or_else(|| self.no_randomness())?;
        store::write_json(
            &path,
            "the installation id",
            &json!({ "id": id, "created_at": store::now() }),
            self.product.id,
        )?;
        Ok(id)
    }

    /// Queue one failure, when the user agreed to send errors. `cause_id` is
    /// the declared cause's id when the product knows it.
    pub fn failure(&self, failure: &Failure, cause_id: Option<&str>) {
        self.record(&events::FAILURE, || {
            self.failure_properties(failure, cause_id)
        });
        self.note_failure(failure);
    }

    /// Queue one finished command, when the user agreed to send usage. The
    /// command is its name only (`pairs import`), never its arguments.
    pub fn command(&self, command: &str, exit_status: i32, duration: Duration) {
        self.record(&events::CLI_COMMAND, || {
            let mut properties = Map::new();
            properties.insert("command".into(), json!(self.cleaner.clean(command)));
            properties.insert("exit_status".into(), json!(exit_status));
            properties.insert("duration_ms".into(), json!(duration.as_millis() as u64));
            properties
        });
        self.note_command(command, exit_status);
    }

    fn record(&self, event: &'static Event, properties: impl FnOnce() -> Map<String, Value>) {
        match self.effective() {
            Ok(level) if level >= event.consent => {}
            Ok(_) => return,
            Err(failure) => return say_failure(&failure),
        }
        if let Err(failure) = self.queue(event, properties()) {
            say_failure(&failure);
        }
    }

    fn queue(&self, event: &'static Event, properties: Map<String, Value>) -> Result<(), Failure> {
        let event_name = event.name;
        let queue = self
            .queue_directory()
            .ok_or_else(|| self.no_home("an event"))?;
        let installation = self.installation()?;
        let event_id = store::random_id().ok_or_else(|| self.no_randomness())?;
        let session = self.session.clone().unwrap_or_else(|| event_id.clone());
        let mut event = json!({
            "eventId": event_id,
            "appId": self.product.app_id,
            "platform": store::platform(),
            "eventName": event_name,
            "anonymousId": installation,
            "sessionId": session,
            "appVersion": self.product.version,
            "occurredAt": store::now(),
            "properties": Value::Object(properties),
        });
        if let Some(os) = store::os_version() {
            event["osVersion"] = json!(os);
        }
        store::write_json(
            &queue.join(format!("{event_id}.json")),
            "an event",
            &event,
            self.product.id,
        )
    }

    fn failure_properties(&self, failure: &Failure, cause_id: Option<&str>) -> Map<String, Value> {
        let clean = |text: &Option<String>| text.as_deref().map(|text| self.cleaner.clean(text));
        let mut properties = Map::new();
        properties.insert("failure_point".into(), json!(failure.failure_point));
        properties.insert("error_code".into(), json!(failure.code.as_str()));
        properties.insert("severity".into(), json!(failure.severity().as_str()));
        properties.insert("retryable".into(), json!(failure.retryable()));
        properties.insert("outage".into(), json!(failure.outage()));
        properties.insert("service".into(), json!(failure.service));
        properties.insert("impact".into(), json!(clean(&failure.impact)));
        properties.insert("detail".into(), json!(clean(&failure.detail)));
        properties.insert("remedy".into(), json!(clean(&failure.remedy)));
        properties.insert("cause_id".into(), json!(cause_id));
        let context: Map<String, Value> = failure
            .context
            .iter()
            .map(|(key, value)| (key.clone(), json!(self.cleaner.clean(value))))
            .collect();
        properties.insert("context".into(), Value::Object(context));
        let mut causes = Vec::new();
        let mut below = failure.cause.as_deref();
        while let Some(cause) = below {
            causes.push(json!({
                "failure_point": cause.failure_point,
                "error_code": cause.code.as_str(),
                "service": cause.service,
                "detail": clean(&cause.detail),
            }));
            below = cause.cause.as_deref();
        }
        properties.insert("causes".into(), Value::Array(causes));
        properties
    }

    /// Every event waiting to be sent, oldest first, exactly as it will go.
    pub fn queued(&self) -> Result<Vec<Value>, Failure> {
        let Some(queue) = self.queue_directory() else {
            return Ok(Vec::new());
        };
        let entries = match std::fs::read_dir(&queue) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(self.unwritable("the event queue", &queue, &error)),
        };
        let mut events = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|extension| extension.to_str()) != Some("json") {
                continue;
            }
            if let Some(event) =
                store::read_json(&path, "a queued event", self.product.id, self.product.id)?
            {
                events.push((path, event));
            }
        }
        events.sort_by(|left, right| {
            let at = |event: &Value| {
                event
                    .get("occurredAt")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned()
            };
            at(&left.1)
                .cmp(&at(&right.1))
                .then_with(|| left.0.cmp(&right.0))
        });
        Ok(events.into_iter().map(|(_, event)| event).collect())
    }

    fn queued_files(&self) -> Result<Vec<(PathBuf, Value)>, Failure> {
        let queued = self.queued()?;
        let queue = self.queue_directory().unwrap_or_default();
        Ok(queued
            .into_iter()
            .filter_map(|event| {
                let id = event.get("eventId").and_then(Value::as_str)?.to_owned();
                Some((queue.join(format!("{id}.json")), event))
            })
            .collect())
    }

    /// Write every queued event to `path` as one JSON array, for a machine
    /// with no network; answers how many.
    pub fn export(&self, path: &Path) -> Result<usize, Failure> {
        let events = self.queued()?;
        let count = events.len();
        store::write_json(
            path,
            "the exported events",
            &Value::Array(events),
            self.product.id,
        )?;
        Ok(count)
    }

    /// Send every queued event; see [`deliver::flush`].
    pub fn flush(&self) -> Result<Delivered, Failure> {
        deliver::flush(self)
    }

    /// Start `program args…` detached to send the queue, when there is
    /// something to send and somewhere to send it, and return at once. A
    /// command-line product calls this as its command ends, so sending never
    /// holds the user. A failure to start is said on stderr and answered, so
    /// a caller that shows its own state can show it too.
    pub fn spawn_flush(&self, program: &Path, args: &[&str]) -> Option<Failure> {
        match self.effective() {
            Ok(Level::Off) | Err(_) => return None,
            Ok(_) => {}
        }
        if self.collector().is_err() {
            return None;
        }
        let queued = match self.queued() {
            Ok(queued) if queued.is_empty() => return None,
            Ok(queued) => queued.len(),
            Err(failure) => {
                say_failure(&failure);
                return Some(failure);
            }
        };
        let started = Command::new(program)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let error = started.err()?;
        let failure = causes::FLUSH_UNSTARTED.failure(
            DELIVER_POINT,
            self.product.id,
            &[
                ("program", &program.display().to_string()),
                ("error", &error.to_string()),
                ("queued", &queued.to_string()),
                ("product", self.product.id),
            ],
        );
        say_failure(&failure);
        Some(failure)
    }

    /// Ask once, on a terminal, what may be sent. Does nothing when the user
    /// already answered, under `DO_NOT_TRACK`, or when stdin or stderr is not
    /// a terminal, so a script or an agent is never prompted. An answer that
    /// is none of the choices records nothing, and nothing is sent.
    pub fn ask(&self, product_name: &str) {
        if Self::do_not_track()
            || !std::io::stdin().is_terminal()
            || !std::io::stderr().is_terminal()
        {
            return;
        }
        match self.level() {
            Ok(None) => {}
            Ok(Some(_)) => return,
            Err(failure) => return say_failure(&failure),
        }
        let id = self.product.id;
        let mut stderr = std::io::stderr();
        let _ = write!(
            stderr,
            "{product_name} can tell its maintainers when something fails on this machine, so it gets \
             fixed without you writing to anyone. Nothing you work on is sent: no files, no prompts, no \
             command arguments, and your home directory and host name are taken out. Change it any time \
             with `{id} telemetry on|off`.\nSend [e]rrors only, errors and [u]sage, or [n]othing? "
        );
        let _ = stderr.flush();
        let mut answer = String::new();
        if std::io::stdin().lock().read_line(&mut answer).is_err() {
            return;
        }
        let level = match answer.trim().to_lowercase().as_str() {
            "e" | "errors" => Level::Errors,
            "u" | "usage" => Level::Usage,
            "n" | "no" | "nothing" | "off" => Level::Off,
            _ => {
                let _ = writeln!(
                    stderr,
                    "Nothing recorded; nothing is sent until you answer."
                );
                return;
            }
        };
        match self.set_level(level) {
            Ok(()) => {
                let _ = writeln!(stderr, "Telemetry: {}.", level.as_str());
            }
            Err(failure) => say_failure(&failure),
        }
    }

    /// Everything a user needs to know about this installation's telemetry,
    /// as `<product> telemetry status` prints it.
    pub fn status(&self) -> Value {
        let level = match self.level() {
            Ok(Some(level)) => json!(level.as_str()),
            Ok(None) => json!("unanswered"),
            Err(failure) => json!({ "unreadable": failure.detail }),
        };
        let (collector, collector_source) = match self.collector() {
            Ok(collector) => (json!(collector.url), json!(collector.source)),
            Err(failure) => (Value::Null, json!({ "refused": failure.detail })),
        };
        let installation = self
            .file("installation.json")
            .and_then(|path| {
                store::read_json(
                    &path,
                    "the installation id",
                    self.product.id,
                    self.product.id,
                )
                .ok()
                .flatten()
            })
            .and_then(|value| value.get("id").cloned())
            .unwrap_or(Value::Null);
        let queued = match self.queued() {
            Ok(queued) => json!(queued.len()),
            Err(failure) => json!({ "unreadable": failure.detail }),
        };
        let last_delivery = self
            .file("delivery.json")
            .and_then(|path| {
                store::read_json(&path, "the last delivery", self.product.id, self.product.id)
                    .ok()
                    .flatten()
            })
            .unwrap_or(Value::Null);
        json!({
            "product": self.product.id,
            "app_id": self.product.app_id,
            "level": level,
            "do_not_track": Self::do_not_track(),
            "collector": collector,
            "collector_source": collector_source,
            "installation": installation,
            "queued": queued,
            "last_delivery": last_delivery,
            "directory": self.directory.as_ref().map(|directory| self.cleaner.clean(&directory.display().to_string())),
        })
    }

    fn no_home(&self, what: &str) -> Failure {
        causes::STORE_UNWRITABLE.failure(
            store::RECORD_POINT,
            self.product.id,
            &[
                ("what", what),
                ("path", "(none)"),
                (
                    "error",
                    "neither WISENT_TELEMETRY_HOME, XDG_STATE_HOME nor HOME is set",
                ),
                ("directory", "(none)"),
            ],
        )
    }

    fn no_randomness(&self) -> Failure {
        causes::STORE_UNWRITABLE.failure(
            store::RECORD_POINT,
            self.product.id,
            &[
                ("what", "an event"),
                ("path", "(none)"),
                ("error", "the system gave no randomness for its id"),
                (
                    "directory",
                    &self
                        .directory
                        .as_ref()
                        .map(|d| d.display().to_string())
                        .unwrap_or_default(),
                ),
            ],
        )
    }

    fn unwritable(&self, what: &str, path: &Path, error: &std::io::Error) -> Failure {
        causes::STORE_UNWRITABLE.failure(
            store::RECORD_POINT,
            self.product.id,
            &[
                ("what", what),
                ("path", &path.display().to_string()),
                ("error", &error.to_string()),
                (
                    "directory",
                    &self
                        .directory
                        .as_ref()
                        .map(|d| d.display().to_string())
                        .unwrap_or_default(),
                ),
            ],
        )
    }
}

const DELIVER_POINT: &str = "wisent-errors.telemetry.deliver";

/// `https://` with a host, or `http://` whose host is this machine's loopback.
fn acceptable_collector(address: &str) -> bool {
    if let Some(rest) = address.strip_prefix("https://") {
        return !rest.is_empty() && !rest.starts_with('/');
    }
    let Some(rest) = address.strip_prefix("http://") else {
        return false;
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = match authority.strip_prefix('[') {
        Some(bracketed) => bracketed.split(']').next().unwrap_or(""),
        None => authority.split(':').next().unwrap_or(""),
    };
    matches!(host, "127.0.0.1" | "localhost" | "::1")
}

/// Say a telemetry failure once on stderr, the way the crate's other
/// reporters do, and let the product go on.
fn say_failure(failure: &Failure) {
    let detail = failure.detail.as_deref().unwrap_or(failure.code.as_str());
    match failure.remedy.as_deref() {
        Some(remedy) => eprintln!("wisent-errors: telemetry: {detail}; fix: {remedy}"),
        None => eprintln!("wisent-errors: telemetry: {detail}"),
    }
}
