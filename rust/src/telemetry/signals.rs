//! Frustration signals only the client can count, because only it sees the
//! order of what happened (docs/telemetry.md, Frustration signals).
//!
//! The reporter counts two in every product: `frustration.repeat_failure`,
//! the same failure point failing again, and `frustration.usage_loop`, the
//! same command refused as usage (exit 2) again. Each repeat is queued with
//! how many times in a row it happened and how many seconds passed since the
//! previous one. No threshold decides here: how many repeats in how short a
//! time make an alarm, or a question to the user, is the operator's number,
//! read by Echo. A repeat is a second occurrence, so a signal starts at two.
//!
//! What was seen last lives in `signals.json` beside the queue and is kept
//! only under the consent its signal needs: failures under `errors`, commands
//! under `usage`.

use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Map, Value};

use super::{events, say_failure, store, Event, Telemetry};
use crate::Failure;

/// The second occurrence is the first repeat.
const FIRST_REPEAT: u64 = 2;

fn seconds_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or_default()
}

impl Telemetry {
    /// The user asked for help (`--help`, `help`, a Help menu) with
    /// `command` the words before it; queue `frustration.help_after_failure`
    /// when a failure was recorded before, with its failure point and the
    /// seconds since it. Usage consent, as the command name is usage.
    pub fn help(&self, command: &str) {
        match self.effective() {
            Ok(level) if level >= events::HELP_AFTER_FAILURE.consent => {}
            Ok(_) => return,
            Err(failure) => return say_failure(&failure),
        }
        let Some(path) = self.file("signals.json") else {
            return;
        };
        let last = match store::read_json(
            &path,
            "the frustration signals",
            self.product.id,
            self.product.id,
        ) {
            Ok(Some(state)) => state["last_failure"].clone(),
            Ok(None) => return,
            Err(failure) => return say_failure(&failure),
        };
        let (Some(point), Some(at)) = (last["failure_point"].as_str(), last["at"].as_u64()) else {
            return;
        };
        let mut properties = Map::new();
        properties.insert("command".into(), json!(self.cleaner.clean(command)));
        properties.insert("failure_point".into(), json!(point));
        properties.insert(
            "seconds_since_failure".into(),
            json!(seconds_now().saturating_sub(at)),
        );
        if let Err(failure) = self.queue(&events::HELP_AFTER_FAILURE, properties) {
            say_failure(&failure);
        }
    }
}

impl Telemetry {
    /// Note a failure that was queued; queue `frustration.repeat_failure`
    /// when the previous failure was the same failure point.
    pub(super) fn note_failure(&self, failure: &Failure) {
        self.note(
            &events::REPEAT_FAILURE,
            "last_failure",
            "failure_point",
            &failure.failure_point,
            true,
        );
    }

    /// Note a finished command; queue `frustration.usage_loop` when it was
    /// refused as usage and the previous usage refusal was the same command.
    /// A command that was not refused as usage ends the loop.
    pub(super) fn note_command(&self, command: &str, exit_status: i32) {
        let refused = exit_status == 2;
        self.note(
            &events::USAGE_LOOP,
            "last_usage_refusal",
            "command",
            &self.cleaner.clean(command),
            refused,
        );
    }

    fn note(&self, signal: &'static Event, slot: &str, key: &str, value: &str, counts: bool) {
        match self.effective() {
            Ok(level) if level >= signal.consent => {}
            Ok(_) => return,
            Err(failure) => return say_failure(&failure),
        }
        let Some(path) = self.file("signals.json") else {
            return;
        };
        let mut state = match store::read_json(
            &path,
            "the frustration signals",
            self.product.id,
            self.product.id,
        ) {
            Ok(Some(Value::Object(state))) => state,
            Ok(_) => Map::new(),
            Err(failure) => return say_failure(&failure),
        };
        let now = seconds_now();
        let previous = state.get(slot).filter(|last| last[key] == value).cloned();
        if !counts {
            state.remove(slot);
        } else {
            let consecutive = previous
                .as_ref()
                .and_then(|last| last["consecutive"].as_u64())
                .map_or(1, |count| count + 1);
            state.insert(
                slot.to_owned(),
                json!({ key: value, "consecutive": consecutive, "at": now }),
            );
            if consecutive >= FIRST_REPEAT {
                let since = previous
                    .as_ref()
                    .and_then(|last| last["at"].as_u64())
                    .map(|at| now.saturating_sub(at));
                let mut properties = Map::new();
                properties.insert(key.to_owned(), json!(value));
                properties.insert("consecutive".into(), json!(consecutive));
                properties.insert("seconds_since_previous".into(), json!(since));
                if let Err(failure) = self.queue(signal, properties) {
                    say_failure(&failure);
                }
            }
        }
        if let Err(failure) = store::write_json(
            &path,
            "the frustration signals",
            &Value::Object(state),
            self.product.id,
        ) {
            say_failure(&failure);
        }
    }
}
