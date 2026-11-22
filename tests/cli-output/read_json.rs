//! Real tests of `cli_output::read_json`'s refusals, each a declared cause of
//! `wisent_errors.cli_output.read_json`, over files written for each case in
//! the test's own directory under Cargo's target. Each refusal is asserted
//! whole, `{failed}: {cause}; observed: {observed}; fix: {remedy}`, with the
//! operating system's and the decoder's own words computed here.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --test cli-output-read

use std::path::{Path, PathBuf};

use serde::Deserialize;
use wisent_errors::cli_output::{read_json, ReadJsonError};

#[derive(Debug, Deserialize, PartialEq)]
#[allow(dead_code)]
struct Human {
    name: String,
}

/// One case's own directory, removed and made again.
fn place(case: &str) -> PathBuf {
    let directory = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("cli-output").join(case);
    match std::fs::remove_dir_all(&directory) {
        Err(error) if error.kind() != std::io::ErrorKind::NotFound => panic!("{} is there before the case and cannot be removed: {error}", directory.display()),
        _ => {}
    }
    std::fs::create_dir_all(&directory).expect("the test's own directory under the target can be made");
    directory
}

fn refusal(path: &Path) -> ReadJsonError {
    match read_json::<Human>(path) {
        Err(error) => error,
        Ok(read) => panic!("{} was read as {read:?}", path.display()),
    }
}

/// A line of the file as a refusal quotes it.
fn quoted(line: &str) -> String {
    format!("\"{}\"", line.replace('\\', "\\\\").replace('"', "\\\""))
}

#[test]
fn a_json_input_is_read_into_the_type_the_command_reads() {
    let path = place("read").join("human.json");
    std::fs::write(&path, "{\n  \"name\": \"ada\"\n}\n").expect("the input can be written");
    let read = read_json::<Human>(&path).unwrap_or_else(|error| panic!("{error}"));
    assert_eq!(read, Human { name: "ada".to_owned() });
}

#[test]
fn an_absent_input_is_refused() {
    let directory = place("absent");
    let path = directory.join("human.json");
    let error = refusal(&path);
    assert_eq!(error.cause().id, "input-absent");
    let os = std::fs::read(&path).unwrap_err();
    let examined = std::fs::metadata(&path).unwrap_err();
    let cwd = std::env::current_dir().expect("the working directory");
    assert_eq!(
        error.to_string(),
        format!(
            "reading the JSON input {path}: no file is at that path; observed: {path} cannot be examined ({examined}); {directory} exists and holds 0 entries; the operating system answered {os}; fix: name a file that exists, or write it first; a relative path is read from {cwd}",
            path = path.display(),
            directory = directory.display(),
            cwd = cwd.display()
        )
    );
}

#[test]
fn an_unreadable_input_is_refused() {
    use std::os::unix::fs::PermissionsExt;
    let path = place("unreadable").join("human.json");
    std::fs::write(&path, "{\"name\":\"x\"}").expect("the input can be written");
    // No permission for anyone: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o000)).expect("its permissions can be withdrawn");
    let error = refusal(&path);
    let os = std::fs::read(&path).unwrap_err();
    // Owner read and write: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).expect("its permissions can be given back");
    assert_eq!(error.cause().id, "input-not-permitted", "{error}");
    assert_eq!(
        error.to_string(),
        format!(
            "reading the JSON input {path}: the file exists but this process may not read it; observed: {path} is a file of 12 bytes, read-only; the operating system answered {os}; fix: let the user running the command read it (chmod u+r {path}), or run the command as its owner",
            path = path.display()
        )
    );
}

#[test]
fn a_directory_input_is_refused() {
    let path = place("directory");
    let error = refusal(&path);
    let os = std::fs::read(&path).unwrap_err();
    assert_eq!(error.cause().id, "input-is-directory", "{error}");
    assert_eq!(
        error.to_string(),
        format!(
            "reading the JSON input {path}: the path names a directory, not a file; observed: {path} is a directory, writable; the operating system answered {os}; fix: name the JSON file inside it, not the directory",
            path = path.display()
        )
    );
}

#[test]
fn an_input_that_is_not_json_is_refused() {
    let path = place("syntax").join("human.json");
    let body = "{\n  \"name\": nope\n}\n";
    std::fs::write(&path, body).expect("the input can be written");
    let error = refusal(&path);
    let decoder = serde_json::from_str::<Human>(body).unwrap_err();
    assert_eq!(error.cause().id, "input-not-json", "{error}");
    assert_eq!(decoder.line(), 2, "{decoder}");
    assert_eq!(
        error.to_string(),
        format!(
            "decoding the JSON input {path}: the file is not JSON: at line 2, column {column} it holds a character JSON does not allow there; observed: {bytes} bytes, line 2 reads {line}; the decoder answered {decoder}; fix: write valid JSON at line 2 of {path}, or name the file the command expects; `jq . {path}` shows the same place",
            path = path.display(),
            column = decoder.column(),
            bytes = body.len(),
            line = quoted("  \"name\": nope")
        )
    );
}

#[test]
fn a_truncated_input_is_refused() {
    let path = place("truncated").join("human.json");
    let body = "{\"name\": \"x\"";
    std::fs::write(&path, body).expect("the input can be written");
    let error = refusal(&path);
    let decoder = serde_json::from_str::<Human>(body).unwrap_err();
    assert_eq!(error.cause().id, "input-truncated", "{error}");
    assert_eq!(
        error.to_string(),
        format!(
            "decoding the JSON input {path}: the JSON ends before its last value closes, so the file is cut short or still being written; observed: 12 bytes, ending at line {line}, column {column}; the decoder answered {decoder}; fix: finish writing {path}, or write it again whole, before running the command",
            path = path.display(),
            line = decoder.line(),
            column = decoder.column()
        )
    );
}

#[test]
fn an_input_of_the_wrong_shape_is_refused() {
    let path = place("shape").join("human.json");
    let body = "{\"title\": \"x\"}";
    std::fs::write(&path, body).expect("the input can be written");
    let error = refusal(&path);
    let decoder = serde_json::from_str::<Human>(body).unwrap_err();
    assert_eq!(error.cause().id, "input-wrong-shape", "{error}");
    // The refusal says what the decoder expected in its words, never the
    // Rust type the program decodes into.
    assert!(!error.to_string().contains("Human"), "{error}");
    assert_eq!(
        error.to_string(),
        format!(
            "decoding the JSON input {path}: the file is JSON but not the document the command reads: a field is missing, extra, or of another type; observed: at line {line}, column {column}; the decoder answered {decoder}; fix: give {path} at line {line}, column {column} the value the decoder answered it expected there, or name the file meant for this command",
            path = path.display(),
            line = decoder.line(),
            column = decoder.column()
        )
    );
}
