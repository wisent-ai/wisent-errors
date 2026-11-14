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
#[path = "delivery/deliver.rs"]
mod deliver;
pub mod events;
mod signals;
#[path = "delivery/store.rs"]
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
                        "why",
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

mod asked;
mod queued;
