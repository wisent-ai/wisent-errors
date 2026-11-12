//! What telemetry records: failures and commands queued as events, the queue
//! read back and exported, and the queue flushed to the collector.

use super::*;

impl Telemetry {
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

    pub(super) fn record(&self, event: &'static Event, properties: impl FnOnce() -> Map<String, Value>) {
        match self.effective() {
            Ok(level) if level >= event.consent => {}
            Ok(_) => return,
            Err(failure) => return say_failure(&failure),
        }
        if let Err(failure) = self.queue(event, properties()) {
            say_failure(&failure);
        }
    }

    pub(super) fn queue(&self, event: &'static Event, properties: Map<String, Value>) -> Result<(), Failure> {
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

    pub(super) fn failure_properties(&self, failure: &Failure, cause_id: Option<&str>) -> Map<String, Value> {
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

    pub(super) fn queued_files(&self) -> Result<Vec<(PathBuf, Value)>, Failure> {
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
}
