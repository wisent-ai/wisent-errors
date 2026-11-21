//! Real tests of `Failure::new`: an envelope built whole with every field the
//! catalogue derives, written as JSON, rendered and chained, and salvaged by
//! `Failure::or_fallback`; and its refusals, each a declared cause of
//! `wisent_errors.envelope.build`: what the refusal says, the cause it names,
//! and that `Failure::or_fallback` records the same cause instead of refusing.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --test envelope

use wisent_errors::{Code, Failure, Invalid};

fn refusal(point: &str, service: &str) -> Invalid {
    match Failure::new(point, Code::Refused, service) {
        Err(invalid) => invalid,
        Ok(built) => panic!("{point:?} / {service:?} was accepted: {}", built.to_json()),
    }
}

#[test]
fn an_envelope_is_built_with_the_fields_the_catalogue_derives() {
    let below = Failure::new("registry.read", Code::NotFound, "registry")
        .expect("a valid envelope")
        .detail("no key fleet/example-host");
    let built = Failure::new(" stado.fleet.enroll ", Code::InfraDown, " stado ")
        .expect("a valid envelope")
        .impact("  ")
        .detail(" connect ECONNREFUSED 127.0.0.1:9 ")
        .remedy("start the registry on example-host")
        .caused_by(below)
        .with_context("host", "example-host");
    let json = r#"{"failure_point":"stado.fleet.enroll","error_code":"infra_down","service":"stado","impact":null,"severity":"critical","retryable":true,"outage":true,"detail":"connect ECONNREFUSED 127.0.0.1:9","remedy":"start the registry on example-host","cause":{"failure_point":"registry.read","error_code":"not_found","service":"registry","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":"no key fleet/example-host","remedy":null},"context":{"host":"example-host"}}"#;
    assert_eq!(built.to_json(), json);
    assert_eq!(built.render(), format!("infrastructure we depend on is unreachable — our failure; retry later {json}"));
    assert_eq!(
        built.chain(),
        vec!["stado.fleet.enroll [infra_down] connect ECONNREFUSED 127.0.0.1:9".to_owned(), "registry.read [not_found] no key fleet/example-host".to_owned()]
    );
}

#[test]
fn a_malformed_envelope_on_an_error_path_is_salvaged_with_its_gaps_recorded() {
    assert_eq!(
        Failure::or_fallback("  ", Code::Refused, "").to_json(),
        r#"{"failure_point":"unknown","error_code":"refused","service":"unknown","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":null,"remedy":null,"context":{"wisent_errors.failure_point":"absent","wisent_errors.service":"absent"}}"#
    );
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
    assert_eq!(
        invalid.to_string(),
        "building the failure envelope of service stado: segment 2 of the failure point \"stado..enroll\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"stado\",\"\",\"enroll\"]; fix: drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with Failure::or_fallback"
    );
}

#[test]
fn a_segment_starting_with_no_letter_is_refused() {
    let invalid = refusal("Brama.dispatch", "brama");
    assert_eq!(invalid.cause().id, "failure-point-segment-start");
    assert_eq!(
        invalid.to_string(),
        "building the failure envelope of service brama: segment 1 of the failure point \"Brama.dispatch\", \"Brama\", starts with \"B\", and a segment starts with a lowercase letter; observed: segments [\"Brama\",\"dispatch\"]; fix: start the segment with a lowercase letter, as 'brama.dispatch'; on an error path build it with Failure::or_fallback"
    );
}

#[test]
fn a_character_outside_the_grammar_is_refused() {
    let invalid = refusal("stado.fleet enroll", "stado");
    assert_eq!(invalid.cause().id, "failure-point-character");
    assert_eq!(
        invalid.to_string(),
        "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet enroll\", \"fleet enroll\", holds \" \", which is not a lowercase letter, a digit, '-' or '_'; observed: segments [\"stado\",\"fleet enroll\"]; fix: write the point in lowercase letters, digits and single '-' or '_', as 'stado.fleet-enroll'; on an error path build it with Failure::or_fallback"
    );
}

#[test]
fn a_dangling_separator_is_refused() {
    let invalid = refusal("stado.fleet-", "stado");
    assert_eq!(invalid.cause().id, "failure-point-separator");
    assert_eq!(
        invalid.to_string(),
        "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet-\", \"fleet-\", ends with a separator or holds two together, and '-' and '_' only join two words; observed: segments [\"stado\",\"fleet-\"]; fix: keep one '-' or '_' between two words of a segment, as 'stado.fleet'; on an error path build it with Failure::or_fallback"
    );
    let fallback = Failure::or_fallback("stado.fleet-", Code::Refused, "stado");
    assert_eq!(fallback.context.get("wisent_errors.failure_point_cause").map(String::as_str), Some("failure-point-separator"));
}

#[test]
fn an_empty_service_is_refused() {
    let invalid = refusal("stado.fleet.enroll", " ");
    assert_eq!(invalid.cause().id, "service-absent");
    assert_eq!(
        invalid.to_string(),
        "building the failure envelope at stado.fleet.enroll: the service is empty, so the envelope would not say which component failed; observed: service \" \", nothing once the whitespace around it is trimmed; fix: pass the name of the component raising it, as in 'stado'; on an error path build it with Failure::or_fallback, which records the gap in context"
    );
}

/// Defect 9594AF64: every failure that was not an outage rendered as a policy
/// refusal of the request or its credentials. Each code says its own summary
/// and whose it is, and only `refused` names a policy.
#[test]
fn each_code_renders_its_own_summary_and_whose_it_is() {
    let lines = [
        (Code::Config, "our deployment configuration is incomplete or wrong — our failure; retrying will not help"),
        (Code::Auth, "the credentials this command used were rejected — the credentials the request presented; retrying will not help"),
        (Code::NotFound, "what the command asked for is not there — what the request named; retrying will not help"),
        (Code::RateLimit, "an upstream is throttling us — the pace of the requests, not their content; retry later"),
        (Code::Timeout, "an upstream did not answer in time — our failure; retry later"),
        (Code::InfraDown, "infrastructure we depend on is unreachable — our failure; retry later"),
        (Code::Refused, "an explicit policy refused this command — a rule we wrote, not the request's credentials; retrying will not help"),
        (Code::Unknown, "the command failed and we could not attribute the failure — not yet attributed to either side; retrying will not help"),
    ];
    assert_eq!(lines.len(), Code::ALL.len(), "a code without its rendered line");
    for (code, line) in lines {
        let built = Failure::new("stado.fleet.enroll", code, "stado").expect("a valid envelope");
        assert_eq!(built.render(), format!("{line} {}", built.to_json()), "{}", code.as_str());
    }
}
