//! Where telemetry keeps its state, and the small facts about this machine an
//! event carries: a random id, the time, the operating system, and what to
//! clean out of text before it leaves.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::failures as own;
use crate::Failure;

/// The directory a product's telemetry lives in: `WISENT_TELEMETRY_HOME`,
/// else `$XDG_STATE_HOME/<product>/telemetry`, else
/// `~/.local/state/<product>/telemetry`; `None` when not even `HOME` is set.
pub(super) fn directory(product: &str) -> Option<PathBuf> {
    let set = |name: &str| std::env::var_os(name).filter(|value| !value.is_empty());
    if let Some(home) = set("WISENT_TELEMETRY_HOME") {
        return Some(PathBuf::from(home));
    }
    if let Some(state) = set("XDG_STATE_HOME") {
        return Some(PathBuf::from(state).join(product).join("telemetry"));
    }
    set("HOME").map(|home| {
        PathBuf::from(home)
            .join(".local")
            .join("state")
            .join(product)
            .join("telemetry")
    })
}

/// Write `value` to `path` whole: a sibling file renamed over it, so a reader
/// never meets half a file.
pub(super) fn write_json(
    path: &Path,
    what: &str,
    value: &Value,
    service: &str,
) -> Result<(), Failure> {
    write_whole(path, value).map_err(|error| {
        own::TELEMETRY_STORE_STORE_UNWRITABLE.failure(
            RECORD_POINT,
            service,
            &[
                ("what", what),
                ("path", &path.display().to_string()),
                ("why", &error.to_string()),
                ("directory", &directory_of(path).display().to_string()),
            ],
        )
    })
}

/// The directory `path` is written in: `.` for a bare file name.
pub(super) fn directory_of(path: &Path) -> &Path {
    match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    }
}

/// What is at `directory`, for a refusal of a file that could not be
/// written in it.
pub(super) fn directory_state(directory: &Path) -> String {
    let shown = directory.display();
    match fs::metadata(directory) {
        Ok(found) if found.is_dir() => format!("{shown} is a directory"),
        Ok(_) => format!("{shown} is a file, not a directory"),
        Err(error) => format!("{shown} cannot be examined: {error}"),
    }
}

/// [`write_json`]'s write, answering what the system said.
pub(super) fn write_whole(path: &Path, value: &Value) -> std::io::Result<()> {
    fs::create_dir_all(directory_of(path))?;
    let mut partial = path.as_os_str().to_os_string();
    partial.push(".partial");
    let partial = PathBuf::from(partial);
    let mut file = fs::File::create(&partial)?;
    file.write_all(value.to_string().as_bytes())
        .and_then(|()| file.sync_all())?;
    fs::rename(&partial, path)
}

/// The JSON object at `path`, `None` when there is no file, and the refusal
/// naming the file when it holds something else.
pub(super) fn read_json(
    path: &Path,
    what: &str,
    product: &str,
    service: &str,
) -> Result<Option<Value>, Failure> {
    Ok(read_json_sized(path, what, product, service)?.map(|(value, _)| value))
}

/// [`read_json`] with how many bytes the file held, for a refusal of what
/// the object says that names the file's own size.
pub(super) fn read_json_sized(
    path: &Path,
    what: &str,
    product: &str,
    service: &str,
) -> Result<Option<(Value, usize)>, Failure> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(read_refused(path, what, product, service, &error)),
    };
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(value) if value.is_object() => Ok(Some((value, bytes.len()))),
        Ok(_) => Err(unreadable(path, what, product, service, "it is not a JSON object", bytes.len())),
        Err(error) => Err(unreadable(path, what, product, service, &error.to_string(), bytes.len())),
    }
}

/// A file the operating system refused to read, named with what is at its
/// path and what the operating system answered: what it holds is unknown.
fn read_refused(path: &Path, what: &str, product: &str, service: &str, error: &std::io::Error) -> Failure {
    let shown = path.display().to_string();
    let state = match fs::metadata(path) {
        Ok(entry) if entry.is_dir() => format!("{shown} is a directory"),
        Ok(entry) => format!("{shown} is a file of {} bytes", entry.len()),
        Err(examined) => format!("{shown} cannot be examined either: {examined}"),
    };
    own::TELEMETRY_STORE_FILE_READ_REFUSED.failure(
        RECORD_POINT,
        service,
        &[("what", what), ("path", &shown), ("state", &state), ("error", &error.to_string()), ("product", product)],
    )
}

fn unreadable(
    path: &Path,
    what: &str,
    product: &str,
    service: &str,
    error: &str,
    bytes: usize,
) -> Failure {
    own::TELEMETRY_STORE_FILE_UNREADABLE.failure(
        RECORD_POINT,
        service,
        &[
            ("what", what),
            ("path", &path.display().to_string()),
            ("why", error),
            ("bytes", &bytes.to_string()),
            ("product", product),
        ],
    )
}

pub(super) const RECORD_POINT: &str = "wisent-errors.telemetry.record";

/// An answer a refusal quotes, on one line, so the refusal stays one
/// sentence: JSON as its compact form, anything else, such as a page of
/// text, quoted as a JSON string with its line ends escaped.
pub(super) fn one_line(answer: &str) -> String {
    match serde_json::from_str::<Value>(answer) {
        Ok(document) => document.to_string(),
        // discarded: an answer that is not JSON is quoted as the text it is, which is what the refusal shows.
        Err(_) => Value::String(answer.to_owned()).to_string(),
    }
}

/// A random version-4 UUID, or `None` when the system has no randomness to
/// give, in which case nothing is queued under a made-up id.
pub(super) fn random_id() -> Option<String> {
    let mut bytes = u128::to_be_bytes(Default::default());
    getrandom::getrandom(&mut bytes).ok()?;
    bytes[6] = (bytes[6] & 0x0f) | 0x40; /* https://www.rfc-editor.org/rfc/rfc9562.html#section-5.4 */
    bytes[8] = (bytes[8] & 0x3f) | 0x80; /* https://www.rfc-editor.org/rfc/rfc9562.html#section-4.1 */
    let (time_low, rest) = bytes.split_first_chunk()?;
    let (time_mid, rest) = rest.split_first_chunk()?;
    let (version, rest) = rest.split_first_chunk()?;
    let (variant, node) = rest.split_first_chunk()?;
    let node: String = node.iter().map(|byte| format!("{byte:02x}")).collect();
    Some(format!(
        "{:08x}-{:04x}-{:04x}-{:04x}-{node}",
        u32::from_be_bytes(*time_low),
        u16::from_be_bytes(*time_mid),
        u16::from_be_bytes(*version),
        u16::from_be_bytes(*variant),
    ))
}

/// Now on this host's clock, RFC 3339 to the millisecond with the host's
/// offset written out (`2026-11-16T14:03:07.120+01:00`, `+00:00` on a host
/// whose local time is UTC, never `Z`), as stado-wait writes its moments:
/// the moment of the last delivery, which a person reads in `<product>
/// telemetry status`, in their own local time.
pub(super) fn local_now() -> String {
    chrono::Local::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, false)
}

/// Now, as RFC 3339 in UTC with milliseconds.
pub(super) fn now() -> String {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let seconds = elapsed.as_secs();
    let (year, month, day) = civil_from_days((seconds / 86_400) as i64); /* https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap04.html#tag_04_19 */
    let of_day = seconds % 86_400; /* https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap04.html#tag_04_19 */
    let (hour, minute, second) = (of_day / 3600, (of_day % 3600) / 60, of_day % 60); /* https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap04.html#tag_04_19 */
    format!(
        "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{:03}Z",
        elapsed.subsec_millis()
    )
}

/// The proleptic Gregorian date of a day count since 1970-01-01, by Howard
/// Hinnant's `civil_from_days`.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468; /* https://howardhinnant.github.io/date_algorithms.html */
    let era = z.div_euclid(146_097); /* https://howardhinnant.github.io/date_algorithms.html */
    let doe = z.rem_euclid(146_097); /* https://howardhinnant.github.io/date_algorithms.html */
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; /* https://howardhinnant.github.io/date_algorithms.html */
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); /* https://howardhinnant.github.io/date_algorithms.html */
    let mp = (5 * doy + 2) / 153; /* https://howardhinnant.github.io/date_algorithms.html */
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32; /* https://howardhinnant.github.io/date_algorithms.html */
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32; /* https://howardhinnant.github.io/date_algorithms.html */
    let year = yoe + era * 400 + i64::from(month <= 2); /* https://howardhinnant.github.io/date_algorithms.html */
    (year, month, day)
}

/// The collector's name for this operating system: `macos`, `linux`, …,
/// exactly as Rust names it.
pub(super) fn platform() -> &'static str {
    std::env::consts::OS
}

/// The operating system's own version, read from the file it keeps it in;
/// `None` where it cannot be read.
pub(super) fn os_version() -> Option<String> {
    match std::env::consts::OS {
        "macos" => {
            let plist =
                fs::read_to_string("/System/Library/CoreServices/SystemVersion.plist").ok()?;
            let key = plist.find("<key>ProductVersion</key>")?;
            let rest = &plist[key..];
            let (_, after) = rest.split_once("<string>")?;
            let (version, _) = after.split_once("</string>")?;
            Some(format!("macOS {}", version.trim()))
        }
        "linux" => {
            let release = fs::read_to_string("/etc/os-release").ok()?;
            release.lines().find_map(|line| {
                line.strip_prefix("PRETTY_NAME=")
                    .map(|value| value.trim_matches('"').to_owned())
            })
        }
        _ => None,
    }
}

/// This machine's host name, `None` where the system does not give one.
fn host_name() -> Option<String> {
    extern "C" {
        fn gethostname(name: *mut std::ffi::c_char, len: usize) -> std::ffi::c_int;
    }
    let mut buffer = [0u8; 256];
    // SAFETY: the buffer is valid for its whole length, and gethostname writes
    // at most that many bytes.
    let status = unsafe { gethostname(buffer.as_mut_ptr().cast(), buffer.len()) };
    if status != 0 {
        return None;
    }
    let end = buffer
        .iter()
        .position(|&byte| byte == 0)
        .unwrap_or(buffer.len());
    let name = String::from_utf8_lossy(&buffer[..end]).trim().to_owned();
    if name.is_empty() {
        None
    } else {
        Some(name)
    }
}

/// What is taken out of every text before it is queued: the user's home
/// directory, and this machine's host name (with and without its domain).
pub(super) struct Cleaner {
    home: Option<String>,
    hosts: Vec<String>,
}

impl Cleaner {
    pub(super) fn of_this_machine() -> Self {
        let home = std::env::var("HOME")
            .ok()
            .map(|home| home.trim_end_matches('/').to_owned())
            .filter(|home| home.len() > 1);
        let mut hosts = Vec::new();
        if let Some(host) = host_name().filter(|host| host != "localhost") {
            if let Some((short, _)) = host.split_once('.') {
                if !short.is_empty() {
                    hosts.push(short.to_owned());
                }
            }
            hosts.insert(0, host);
        }
        Self { home, hosts }
    }

    pub(super) fn clean(&self, text: &str) -> String {
        let mut cleaned = match &self.home {
            Some(home) => text.replace(home.as_str(), "~"),
            None => text.to_owned(),
        };
        for host in &self.hosts {
            cleaned = cleaned.replace(host.as_str(), "<this-host>");
        }
        cleaned
    }
}
