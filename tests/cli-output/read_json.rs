//! Real tests of `cli_output::read_json`'s refusals, each a declared cause of
//! `wisent_errors.cli_output.read_json`, over files written for each case in
//! the test's own directory under Cargo's target.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --test cli-output-read

use std::path::PathBuf;

use serde::Deserialize;
use wisent_errors::cli_output::{read_json, ReadJsonError};

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct Human {
    name: String,
}

/// One case's own directory, removed and made again.
fn place(case: &str) -> PathBuf {
    let directory = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("cli-output").join(case);
    let _ = std::fs::remove_dir_all(&directory);
    std::fs::create_dir_all(&directory).expect("the test's own directory under the target can be made");
    directory
}

fn refusal(path: &std::path::Path) -> ReadJsonError {
    match read_json::<Human>(path) {
        Err(error) => error,
        Ok(read) => panic!("{} was read as {read:?}", path.display()),
    }
}

#[test]
fn an_absent_input_is_refused() {
    let path = place("absent").join("human.json");
    let error = refusal(&path);
    assert_eq!(error.cause().id, "input-absent");
    let said = error.to_string();
    assert!(said.starts_with(&format!("reading the JSON input {}: no file is at that path; observed: ", path.display())), "{said}");
    assert!(said.contains("exists and holds 0 entries"), "{said}");
}

#[test]
fn an_unreadable_input_is_refused() {
    use std::os::unix::fs::PermissionsExt;
    let path = place("unreadable").join("human.json");
    std::fs::write(&path, "{\"name\":\"x\"}").expect("the input can be written");
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o000)).expect("its permissions can be withdrawn");
    let error = refusal(&path);
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).expect("its permissions can be given back");
    assert_eq!(error.cause().id, "input-not-permitted", "{error}");
    assert!(error.to_string().contains("chmod u+r"), "{error}");
}

#[test]
fn a_directory_input_is_refused() {
    let path = place("directory");
    let error = refusal(&path);
    assert_eq!(error.cause().id, "input-is-directory", "{error}");
    assert!(error.to_string().contains("is a directory"), "{error}");
}

#[test]
fn an_input_that_is_not_json_is_refused() {
    let path = place("syntax").join("human.json");
    std::fs::write(&path, "{\n  \"name\": nope\n}\n").expect("the input can be written");
    let error = refusal(&path);
    assert_eq!(error.cause().id, "input-not-json", "{error}");
    assert!(error.to_string().contains("at line 2, column"), "{error}");
    assert!(error.to_string().contains("line 2 reads \"  \\\"name\\\": nope\""), "{error}");
}

#[test]
fn a_truncated_input_is_refused() {
    let path = place("truncated").join("human.json");
    std::fs::write(&path, "{\"name\": \"x\"").expect("the input can be written");
    let error = refusal(&path);
    assert_eq!(error.cause().id, "input-truncated", "{error}");
    assert!(error.to_string().contains("12 bytes"), "{error}");
}

#[test]
fn an_input_of_the_wrong_shape_is_refused() {
    let path = place("shape").join("human.json");
    std::fs::write(&path, "{\"title\": \"x\"}").expect("the input can be written");
    let error = refusal(&path);
    assert_eq!(error.cause().id, "input-wrong-shape", "{error}");
    assert!(error.to_string().contains("as cli_output_read::Human"), "{error}");
    assert!(error.to_string().contains("missing field `name`"), "{error}");
}
