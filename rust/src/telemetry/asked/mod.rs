//! Telemetry's answers to its owner: a flush spawned in the background, the
//! consent asked for, the status shown, and the refusals its paths raise.

use super::*;

impl Telemetry {
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
                ("why", &error.to_string()),
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

    pub(super) fn no_home(&self, what: &str) -> Failure {
        causes::STORE_UNWRITABLE.failure(
            store::RECORD_POINT,
            self.product.id,
            &[
                ("what", what),
                ("path", "(none)"),
                (
                    "why",
                    "neither WISENT_TELEMETRY_HOME, XDG_STATE_HOME nor HOME is set",
                ),
                ("directory", "(none)"),
            ],
        )
    }

    pub(super) fn no_randomness(&self) -> Failure {
        causes::STORE_UNWRITABLE.failure(
            store::RECORD_POINT,
            self.product.id,
            &[
                ("what", "an event"),
                ("path", "(none)"),
                ("why", "the system gave no randomness for its id"),
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

    pub(super) fn unwritable(&self, what: &str, path: &Path, error: &std::io::Error) -> Failure {
        causes::STORE_UNWRITABLE.failure(
            store::RECORD_POINT,
            self.product.id,
            &[
                ("what", what),
                ("path", &path.display().to_string()),
                ("why", &error.to_string()),
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
