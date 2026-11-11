//! Sending the queue to the collector, oldest event first, and keeping the
//! outcome of the last attempt where `status` reads it.

use serde_json::{json, Value};

use super::causes::{
    COLLECTOR_ANSWER_UNREADABLE, COLLECTOR_FAILED, COLLECTOR_REFUSED, COLLECTOR_UNREACHABLE,
};
use super::{store, Collector, Level, Telemetry, DELIVER_POINT};
use crate::Failure;

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
            sent: 0,
            remaining: queued.len(),
            stopped: None,
            skipped: Some(skipped),
        });
    }
    let collector = match telemetry.collector() {
        Ok(Collector { url, .. }) => url,
        Err(failure) => {
            let delivered = Delivered {
                sent: 0,
                remaining: queued.len(),
                stopped: Some(failure),
                skipped: None,
            };
            keep(telemetry, &delivered)?;
            return Ok(delivered);
        }
    };
    let agent = ureq::AgentBuilder::new().build();
    let product = telemetry.product().id;
    let app = telemetry.product().app_id;
    let mut sent = 0;
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
            ];
            values.extend(extra.iter().map(|(key, value)| (*key, value.clone())));
            values
        };
        let answer = agent
            .post(&collector)
            .set("Content-Type", "application/json")
            .send_string(&event.to_string());
        let refusal = match answer {
            Ok(response) => {
                let status = response.status();
                let body = response.into_string().unwrap_or_default();
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
                let values = values(&[("status", status.to_string()), ("answer", body)]);
                COLLECTOR_ANSWER_UNREADABLE.failure(DELIVER_POINT, product, &borrowed(&values))
            }
            Err(ureq::Error::Status(status, response)) => {
                let body = response.into_string().unwrap_or_default();
                // A server error is the collector's own failure, whatever its
                // body; below that, the collector refuses with a JSON object
                // and anything else came from an address that is not it.
                let collector_said =
                    serde_json::from_str::<Value>(&body).is_ok_and(|answer| answer.is_object());
                let values = values(&[("status", status.to_string()), ("answer", body)]);
                let cause = if status >= 500 {
                    &COLLECTOR_FAILED
                } else if collector_said {
                    &COLLECTOR_REFUSED
                } else {
                    &COLLECTOR_ANSWER_UNREADABLE
                };
                cause.failure(DELIVER_POINT, product, &borrowed(&values))
            }
            Err(ureq::Error::Transport(transport)) => {
                let values = values(&[("error", transport.to_string())]);
                COLLECTOR_UNREACHABLE.failure(DELIVER_POINT, product, &borrowed(&values))
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
    record["at"] = json!(store::now());
    store::write_json(&path, "the last delivery", &record, telemetry.product().id)
}
