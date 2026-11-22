//! Sending the queue to the collector, oldest event first, and keeping the
//! outcome of the last attempt where `status` reads it.

use serde_json::{json, Value};
use stado_wait::Kind;

use super::{store, Collector, Level, Telemetry, DELIVER_POINT};
use crate::failures as own;
use crate::Failure;

/// What the collector answered to one event, its body read inside the wait.
struct Answered {
    status: u16,
    /// The answer carried an HTTP error status (ureq's `Error::Status`).
    refused: bool,
    body: std::io::Result<String>,
}

/// Send one event and read the whole answer: the work one wait stands on.
fn post(agent: &ureq::Agent, collector: &str, event: &str) -> Result<Answered, ureq::Transport> {
    let (response, refused) = match agent
        .post(collector)
        .set("Content-Type", "application/json")
        .send_string(event)
    {
        Ok(response) => (response, false),
        Err(ureq::Error::Status(_, response)) => (response, true),
        Err(ureq::Error::Transport(transport)) => return Err(transport),
    };
    Ok(Answered {
        status: response.status(),
        refused,
        body: response.into_string(),
    })
}

/// What one flush did.
#[derive(Debug)]
pub struct Delivered {
    /// Events the collector accepted and the queue no longer holds.
    pub sent: usize,
    /// Events still waiting.
    pub remaining: usize,
    /// Why sending stopped before the queue was empty: the collector's
    /// refusal, a transport error, or a collector address that is refused.
    /// `None` when every event went, or when the user's level sends nothing.
    pub stopped: Option<Failure>,
    /// Why nothing was attempted: `off`, `unanswered` or `DO_NOT_TRACK`.
    pub skipped: Option<&'static str>,
}

impl Delivered {
    pub fn to_json(&self) -> Value {
        json!({
            "sent": self.sent,
            "remaining": self.remaining,
            "stopped": self.stopped.as_ref().map(|failure| json!({
                "error_code": failure.code.as_str(),
                "detail": failure.detail,
                "remedy": failure.remedy,
            })),
            "skipped": self.skipped,
        })
    }
}

/// Send every queued event to the collector. Each one the collector accepts
/// (`{"ok": true}`) leaves the queue; the first refusal or transport error
/// stops the flush, so the rest wait for the next. The outcome is kept in
/// `delivery.json`. Fails only when the store itself cannot be read or
/// written.
pub(super) fn flush(telemetry: &Telemetry) -> Result<Delivered, Failure> {
    let queued = telemetry.queued_files()?;
    let skipped = if Telemetry::do_not_track() {
        Some("DO_NOT_TRACK")
    } else {
        match telemetry.level()? {
            None => Some("unanswered"),
            Some(Level::Off) => Some("off"),
            Some(_) => None,
        }
    };
    if let Some(skipped) = skipped {
        return Ok(Delivered {
            sent: Default::default(),
            remaining: queued.len(),
            stopped: None,
            skipped: Some(skipped),
        });
    }
    let collector = match telemetry.collector() {
        Ok(Collector { url, .. }) => url,
        Err(failure) => {
            let delivered = Delivered {
                sent: Default::default(),
                remaining: queued.len(),
                stopped: Some(failure),
                skipped: None,
            };
            keep(telemetry, &delivered)?;
            return Ok(delivered);
        }
    };
    // Each send is a stado-wait wait: in the register `stado waits` lists for
    // as long as it stands, said on stderr when nothing tells it from a stall
    // or once it is past the time its earlier sends took, and measured. It
    // ends on evidence: the collector answers, refuses or closes, or this
    // process is ended; no time is guessed for it.
    let agent = ureq::AgentBuilder::new().build();
    let product = telemetry.product().id;
    let app = telemetry.product().app_id;
    let mut sent: usize = Default::default();
    let mut stopped = None;
    for (index, (path, event)) in queued.iter().enumerate() {
        let event_id = event.get("eventId").and_then(Value::as_str).unwrap_or("");
        let waiting = (queued.len() - index).to_string();
        let values = |extra: &[(&'static str, String)]| {
            let mut values: Vec<(&str, String)> = vec![
                ("event", event_id.to_owned()),
                ("collector", collector.clone()),
                ("queued", waiting.clone()),
                ("app", app.to_owned()),
                ("product", product.to_owned()),
                ("accepted", r#"{"ok": true}"#.to_owned()),
            ];
            values.extend(extra.iter().map(|(key, value)| (*key, value.clone())));
            values
        };
        let answer = stado_wait::blocking_as(
            Kind::Network,
            "telemetry delivery",
            format!("POST event {event_id}"),
            &collector,
            || post(&agent, &collector, &event.to_string()),
        );
        let refusal = match answer {
            Err(transport) => {
                let values = values(&[("why", transport.to_string())]);
                own::TELEMETRY_DELIVER_COLLECTOR_UNREACHABLE.failure(
                    DELIVER_POINT,
                    product,
                    &borrowed(&values),
                )
            }
            Ok(Answered {
                status,
                body: Err(error),
                ..
            }) => {
                let why = format!("HTTP {status} came and its body could not be read: {error}");
                let values = values(&[("why", why)]);
                own::TELEMETRY_DELIVER_COLLECTOR_UNREACHABLE.failure(
                    DELIVER_POINT,
                    product,
                    &borrowed(&values),
                )
            }
            Ok(Answered {
                status,
                refused: false,
                body: Ok(body),
            }) => {
                let accepted = serde_json::from_str::<Value>(&body)
                    .ok()
                    .and_then(|answer| answer.get("ok").and_then(Value::as_bool))
                    == Some(true);
                if accepted {
                    if let Err(error) = std::fs::remove_file(path) {
                        if error.kind() != std::io::ErrorKind::NotFound {
                            return Err(telemetry.unwritable("a sent event", path, &error));
                        }
                    }
                    sent += 1;
                    continue;
                }
                let values = values(&[("status", status.to_string()), ("answer", store::one_line(&body))]);
                own::TELEMETRY_DELIVER_COLLECTOR_ANSWER_UNREADABLE.failure(
                    DELIVER_POINT,
                    product,
                    &borrowed(&values),
                )
            }
            Ok(Answered {
                status,
                refused: true,
                body: Ok(body),
            }) => {
                // A server error is the collector's own failure, whatever its
                // body; below that, the collector refuses with a JSON object
                // and anything else came from an address that is not it.
                let collector_said =
                    serde_json::from_str::<Value>(&body).is_ok_and(|answer| answer.is_object());
                let values = values(&[("status", status.to_string()), ("answer", store::one_line(&body))]);
                // The 5xx server error class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
                let cause = if status >= 500 {
                    &own::TELEMETRY_DELIVER_COLLECTOR_FAILED
                } else if collector_said {
                    &own::TELEMETRY_DELIVER_COLLECTOR_REFUSED
                } else {
                    &own::TELEMETRY_DELIVER_COLLECTOR_ANSWER_UNREADABLE
                };
                cause.failure(DELIVER_POINT, product, &borrowed(&values))
            }
        };
        stopped = Some(refusal);
        break;
    }
    let delivered = Delivered {
        sent,
        remaining: queued.len() - sent,
        stopped,
        skipped: None,
    };
    keep(telemetry, &delivered)?;
    Ok(delivered)
}

fn borrowed<'a>(values: &'a [(&'a str, String)]) -> Vec<(&'a str, &'a str)> {
    values
        .iter()
        .map(|(key, value)| (*key, value.as_str()))
        .collect()
}

fn keep(telemetry: &Telemetry, delivered: &Delivered) -> Result<(), Failure> {
    let Some(path) = telemetry.file("delivery.json") else {
        return Ok(());
    };
    let mut record = delivered.to_json();
    record["at"] = json!(store::local_now());
    store::write_json(&path, "the last delivery", &record, telemetry.product().id)
}
