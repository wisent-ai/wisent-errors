//! The user's answer: the level they agreed to send, kept and read back, and
//! what is actually sent under it.

use super::*;

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
            other => Err(own::TELEMETRY_CONSENT_LEVEL_UNKNOWN.failure(
                CONSENT_POINT,
                product,
                &[("level", other)],
            )),
        }
    }
}

impl Telemetry {
    /// The level the user chose, `None` while unanswered.
    pub fn level(&self) -> Result<Option<Level>, Failure> {
        let Some(path) = self.file("consent.json") else {
            return Ok(None);
        };
        let Some((consent, size)) = store::read_json_sized(
            &path,
            "the telemetry consent",
            self.product.id,
            self.product.id,
        )?
        else {
            return Ok(None);
        };
        // fallback: a consent record naming no level reads as empty, which Level::parse refuses below.
        let level = consent.get("level").and_then(Value::as_str).unwrap_or("");
        Level::parse(level, self.product.id).map(Some).map_err(|refused| {
            own::TELEMETRY_STORE_FILE_UNREADABLE.failure(
                CONSENT_POINT,
                self.product.id,
                &[
                    ("what", "the telemetry consent"),
                    ("path", &path.display().to_string()),
                    ("why", &format!("level {level:?} is not off, errors or usage")),
                    ("bytes", &size.to_string()),
                    ("product", self.product.id),
                ],
            )
            .caused_by(refused)
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
    pub(super) fn effective(&self) -> Result<Level, Failure> {
        if Self::do_not_track() {
            return Ok(Level::Off);
        }
        // fallback: no consent recorded sends nothing: the level is off.
        Ok(self.level()?.unwrap_or(Level::Off))
    }
}
