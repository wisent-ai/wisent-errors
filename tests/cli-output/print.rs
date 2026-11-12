//! Real tests of `cli_output::output`'s refusals, each a declared cause of
//! `wisent_errors.cli_output.print`. A closed or full standard output can
//! only be met by a process whose standard output is that, and this crate
//! ships no program of its own; tests/untested-causes.json lists those two.
//!
//!   cargo test --manifest-path rust/Cargo.toml --test cli-output-print

use std::collections::HashMap;

use wisent_errors::cli_output::output;

#[test]
fn a_result_json_cannot_hold_is_refused() {
    let mut result: HashMap<(u8, u8), u8> = HashMap::new();
    result.insert((1, 2), 3);
    let error = output::<_, serde_json::Error>(&result, false).expect_err("a map keyed by pairs has no JSON form");
    let said = error.to_string();
    assert!(said.starts_with("turning the result of type std::collections::hash::map::HashMap<(u8, u8), u8> into JSON: the result holds a value JSON has no form for"), "{said}");
    assert!(said.contains("observed: the encoder answered key must be a string"), "{said}");
}
