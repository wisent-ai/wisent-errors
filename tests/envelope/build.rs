//! Real tests of `Failure::new`'s refusals, each a declared cause of
//! `wisent_errors.envelope.build`: what the refusal says, the cause it names,
//! and that `Failure::or_fallback` records the same cause instead of refusing.
//!
//!   cargo test --manifest-path rust/Cargo.toml --test envelope

use wisent_errors::{Code, Failure, Invalid};

fn refusal(point: &str, service: &str) -> Invalid {
    match Failure::new(point, Code::Refused, service) {
        Err(invalid) => invalid,
        Ok(built) => panic!("{point:?} / {service:?} was accepted: {}", built.to_json()),
    }
}

#[test]
fn an_empty_point_is_refused() {
    let invalid = refusal("   ", "stado");
    assert_eq!(invalid.cause().id, "failure-point-absent");
    assert_eq!(
        invalid.to_string(),
        "building the failure envelope of service stado: the failure point is empty, so the envelope would not say where it broke; observed: failure_point \"   \", nothing once the whitespace around it is trimmed; fix: pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with Failure::or_fallback, which records the gap in context instead of refusing"
    );
}

#[test]
fn an_empty_segment_is_refused() {
    let invalid = refusal("stado..enroll", "stado");
    assert_eq!(invalid.cause().id, "failure-point-segment-empty");
    assert!(invalid.to_string().contains("segment 2 of the failure point \"stado..enroll\" is empty"), "{invalid}");
    assert!(invalid.to_string().contains("observed: segments [\"stado\",\"\",\"enroll\"]"), "{invalid}");
}

#[test]
fn a_segment_starting_with_no_letter_is_refused() {
    let invalid = refusal("Brama.dispatch", "brama");
    assert_eq!(invalid.cause().id, "failure-point-segment-start");
    assert!(invalid.to_string().contains("segment 1 of the failure point \"Brama.dispatch\", \"Brama\", starts with \"B\""), "{invalid}");
    assert!(invalid.to_string().contains("as 'brama.dispatch'"), "{invalid}");
}

#[test]
fn a_character_outside_the_grammar_is_refused() {
    let invalid = refusal("stado.fleet enroll", "stado");
    assert_eq!(invalid.cause().id, "failure-point-character");
    assert!(invalid.to_string().contains("\"fleet enroll\", holds \" \""), "{invalid}");
    assert!(invalid.to_string().contains("as 'stado.fleet-enroll'"), "{invalid}");
}

#[test]
fn a_dangling_separator_is_refused() {
    let invalid = refusal("stado.fleet-", "stado");
    assert_eq!(invalid.cause().id, "failure-point-separator");
    let fallback = Failure::or_fallback("stado.fleet-", Code::Refused, "stado");
    assert_eq!(fallback.context.get("wisent_errors.failure_point_cause").map(String::as_str), Some("failure-point-separator"));
}

#[test]
fn an_empty_service_is_refused() {
    let invalid = refusal("stado.fleet.enroll", " ");
    assert_eq!(invalid.cause().id, "service-absent");
    assert!(invalid.to_string().starts_with("building the failure envelope at stado.fleet.enroll: the service is empty"), "{invalid}");
    assert!(invalid.to_string().contains("observed: service \" \""), "{invalid}");
}
