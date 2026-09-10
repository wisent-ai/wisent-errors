use wisent_errors::{trim_detail, trim_detail_at_word_edge, Code, Failure, Invalid, Severity};

#[test]
fn derived_fields_cannot_be_chosen_at_the_call_site() {
    let failure = Failure::new("brama.dispatch.bounded-rotation", Code::RateLimit, "brama")
        .expect("valid")
        .impact("one model request")
        .detail("all bounded 'codex' credentials unavailable for agent");
    assert!(failure.retryable());
    assert!(!failure.outage());
    assert_eq!(failure.severity(), Severity::Warning);
}

#[test]
fn an_empty_segment_is_still_refused() {
    let refused = Failure::new("brama..dispatch", Code::Unknown, "brama");
    assert!(matches!(refused, Err(Invalid::FailurePoint(_))));
}

#[test]
fn an_absent_detail_is_null_rather_than_missing() {
    let quiet = Failure::new("accounts.create", Code::NotFound, "growth-tactics").expect("valid");
    assert!(quiet.to_json().contains("\"detail\":null"));
    assert!(quiet.to_json().contains("\"impact\":null"));
}

#[test]
fn reporting_a_failure_never_fails() {
    let salvaged = Failure::or_fallback("Not A Point", Code::Unknown, "");
    assert_eq!(salvaged.failure_point, "Not A Point");
    assert_eq!(salvaged.service, "unknown");
    assert_eq!(
        salvaged
            .context
            .get("wisent_errors.failure_point")
            .map(String::as_str),
        Some("malformed")
    );
    assert_eq!(
        salvaged
            .context
            .get("wisent_errors.service")
            .map(String::as_str),
        Some("absent")
    );
}

#[test]
fn an_off_catalogue_code_becomes_the_fallback() {
    assert_eq!(Code::or_fallback("no_such_code"), Code::Unknown);
    assert_eq!(Code::or_fallback("rate_limit"), Code::RateLimit);
}

#[test]
fn a_products_own_bound_is_the_products_to_choose() {
    let long = "x".repeat(600);
    assert_eq!(trim_detail(&long, 500).chars().count(), 500);
    assert_eq!(trim_detail("short", 500), "short");
}

#[test]
fn the_default_cut_is_hard_because_that_is_what_the_fleet_emits() {
    let spaced = format!("{} tail", "x".repeat(298));
    assert_eq!(trim_detail(&spaced, 300).chars().count(), 300);
}

#[test]
fn the_word_edge_is_measured_in_characters_not_bytes() {
    // 100 CJK characters, a space, then more: the byte offset of that space is
    // 300, which passed a character guard of 300-24 and discarded two thirds of
    // the allowed detail.
    let text = format!("{} {}", "\u{8a00}".repeat(100), "\u{8a00}".repeat(400));
    assert_eq!(
        trim_detail_at_word_edge(&text, 300, 24).chars().count(),
        300
    );
}

#[test]
fn the_chain_keeps_the_reason_the_bottom_layer_gave() {
    let vault = Failure::new("skarbiec.authority.redeem", Code::Auth, "skarbiec")
        .expect("valid")
        .impact("one capability redemption")
        .detail("redemption denied: no value at provider:codex:sub#value");
    let provider = Failure::new("brama.gateway.oauth-refresh", Code::Auth, "brama")
        .expect("valid")
        .impact("one credential refresh")
        .detail("invalid_grant -- Refresh token not found or invalid")
        .caused_by(vault);
    let caller = Failure::new("brama.dispatch.bounded-rotation", Code::RateLimit, "brama")
        .expect("valid")
        .impact("one model request")
        .detail("all bounded 'codex' credentials unavailable for agent")
        .caused_by(provider);

    let chain = caller.chain();
    assert_eq!(chain.len(), 3);
    assert!(chain[2].contains("redemption denied"));
}

#[test]
fn server_errors_are_never_not_found() {
    assert_eq!(Code::from_upstream_status(503), Code::InfraDown);
    assert_eq!(Code::from_upstream_status(404), Code::NotFound);
    assert_eq!(Code::from_upstream_status(429), Code::RateLimit);
    assert_eq!(Code::from_upstream_status(418), Code::Unknown);
}
