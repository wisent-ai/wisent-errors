//! What a raised `Declared` says and how a caller several layers above finds
//! it: its refusal with the values its site knew, the declared cause beneath
//! an error that wraps it, and the full id the functionality lists it under.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --test declared

use wisent_errors::failures::{ENVELOPE_BUILD, ENVELOPE_BUILD_FAILURE_POINT_ABSENT};
use wisent_errors::Declared;

fn absent() -> Declared {
    Declared::new(
        &ENVELOPE_BUILD_FAILURE_POINT_ABSENT,
        &[("service", "kupiec"), ("quoted_point", "\"\""), ("fallback", "Failure::or_fallback")],
    )
}

/// An error of a product's own layer that carries the declared cause as its
/// source, as a product's wrapper does.
#[derive(Debug)]
struct Wrapping(Declared);

impl std::fmt::Display for Wrapping {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("starting the order")
    }
}

impl std::error::Error for Wrapping {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.0)
    }
}

#[test]
fn a_declared_cause_says_its_refusal_with_the_values_its_site_knew() {
    assert_eq!(
        absent().to_string(),
        "building the failure envelope of service kupiec: the failure point is empty, so the envelope would not say where it broke; observed: failure_point \"\", nothing once the whitespace around it is trimmed; fix: pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with Failure::or_fallback, which records the gap in context instead of refusing"
    );
}

#[test]
fn the_declared_cause_beneath_a_wrapping_error_is_found() {
    let wrapped = Wrapping(absent());
    let found = Declared::in_chain(&wrapped).map(|declared| declared.cause.id);
    assert_eq!(found, Some("failure-point-absent"));
    let plain = std::io::Error::other("no cause declared here");
    assert_eq!(Declared::in_chain(&plain), None);
}

#[test]
fn the_full_id_names_the_functionality_that_lists_the_cause() {
    assert_eq!(absent().code(&[&ENVELOPE_BUILD]), "wisent_errors.envelope.build.failure-point-absent");
    assert_eq!(absent().code(&[]), "failure-point-absent");
}
