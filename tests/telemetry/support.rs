//! Support reports against a real support service, wisent-customer-support,
//! named by `WISENT_SUPPORT_TEST_URL` (its `/v1/public/reports`) with the
//! service token `WISENT_SUPPORT_TEST_TOKEN` an agent replies with.

use std::net::TcpListener;

use serde_json::{json, Value};
use wisent_errors::telemetry::{Level, Report, PUBLIC_SUPPORT};

use crate::{collector, sample_failure, Case};

fn support() -> String {
    std::env::var("WISENT_SUPPORT_TEST_URL").expect(
        "set WISENT_SUPPORT_TEST_URL to a support service's /v1/public/reports: these cases run against a real one",
    )
}

fn token() -> String {
    std::env::var("WISENT_SUPPORT_TEST_TOKEN")
        .expect("set WISENT_SUPPORT_TEST_TOKEN to that service's support token, which the agent's reply needs")
}

fn report(description: &str) -> Report<'_> {
    Report {
        subject: Some("pairs import fails"),
        description,
        email: None,
        with_failure: true,
    }
}

/// The service's own API, as a support agent uses it.
fn agent(path: &str) -> String {
    let base = support();
    let origin = &base[..base.find("/v1/").expect("the address has the /v1/ path")];
    format!("{origin}{path}")
}

#[test]
fn a_report_reaches_support_and_its_reply_is_read_back() {
    let mut case = Case::new("support-report");
    std::env::set_var("WISENT_SUPPORT_URL", support());
    let telemetry = case.telemetry("wisent-errors-test-cli");
    telemetry
        .set_level(Level::Errors)
        .expect("the level is kept");
    telemetry.failure(&sample_failure(), Some("pairs-unreadable"));
    let filed = telemetry
        .file_report(&report("ster pairs import stops on a file that opens fine"))
        .expect("support takes the report");
    case.note("filed", filed.clone());
    let id = filed["id"].as_str().expect("an id").to_owned();
    assert_eq!(filed["with_failure"], true);
    let kept: Value = serde_json::from_str(
        &std::fs::read_to_string(filed["kept"].as_str().expect("where the key is kept"))
            .expect("the kept report"),
    )
    .expect("JSON");
    assert_eq!(kept["id"], id.as_str());
    assert!(kept["access_key"].as_str().is_some_and(|key| key.len() >= 40));

    let listed = ureq::get(&agent("/v1/support/tickets"))
        .set("x-support-token", &token())
        .call()
        .expect("the agent lists tickets")
        .into_string()
        .expect("the answer");
    let tickets: Value = serde_json::from_str(&listed).expect("JSON");
    let ticket = tickets
        .as_array()
        .expect("a list")
        .iter()
        .find(|ticket| ticket["public_id"] == id.as_str())
        .expect("the report is a ticket")
        .clone();
    let report = &ticket["metadata"]["installation_report"];
    assert_eq!(report["product"], "wisent-errors-test");
    assert_eq!(report["failure"]["cause_id"], "pairs-unreadable");
    assert!(!report["installation"].as_str().unwrap_or("").is_empty());
    ureq::post(&agent(&format!(
        "/v1/support/tickets/{}/reply",
        ticket["id"].as_str().expect("the ticket id")
    )))
    .set("x-support-token", &token())
    .set("content-type", "application/json")
    .send_string(&json!({ "body_text": "Fixed in the next release." }).to_string())
    .expect("the agent replies");

    let reports = telemetry.reports().expect("the kept reports read");
    case.note("reports", json!(reports));
    let read = reports
        .iter()
        .find(|read| read["id"] == id.as_str())
        .expect("the report reads back");
    assert_eq!(read["status"], "waiting_on_customer");
    assert_eq!(read["replies"][0]["text"], "Fixed in the next release.");
}

#[test]
fn a_report_without_a_description_is_refused_before_sending() {
    let mut case = Case::new("support-no-description");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&report("   "))
        .expect_err("an empty description is refused");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "refused");
    assert!(refused
        .remedy
        .expect("a fix")
        .contains("wisent-errors-test support report --description"));
    assert_eq!(telemetry.reports().expect("nothing kept").len(), 0);
}

#[test]
fn a_plain_http_support_address_is_refused_by_name() {
    let mut case = Case::new("support-plain-http");
    std::env::set_var("WISENT_SUPPORT_URL", "http://support.example/v1/public/reports");
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&report("something failed"))
        .expect_err("plain http to another host is refused");
    case.note("refusal", json!(refused.detail));
    assert!(refused
        .detail
        .expect("a sentence")
        .contains("WISENT_SUPPORT_URL holds http://support.example"));
    std::env::remove_var("WISENT_SUPPORT_URL");
    assert_eq!(
        telemetry.support_address().expect("the public one"),
        (PUBLIC_SUPPORT.to_owned(), "wisent-errors")
    );
}

#[test]
fn a_report_support_refuses_says_why() {
    let mut case = Case::new("support-refused");
    std::env::set_var("WISENT_SUPPORT_URL", support());
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&Report {
            email: Some("not an address"),
            ..report("something failed")
        })
        .expect_err("support refuses the email");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "refused");
    assert!(refused
        .detail
        .expect("a sentence")
        .contains("support refused HTTP 400: email \"not an address\" is not an email address"));
    assert_eq!(telemetry.reports().expect("nothing kept").len(), 0);
}

#[test]
fn an_unreachable_support_files_nothing() {
    let mut case = Case::new("support-unreachable");
    let port = TcpListener::bind("127.0.0.1:0")
        .expect("a free port")
        .local_addr()
        .expect("its address")
        .port();
    std::env::set_var(
        "WISENT_SUPPORT_URL",
        format!("http://127.0.0.1:{port}/v1/public/reports"),
    );
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&report("something failed"))
        .expect_err("nothing answers");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "infra_down");
    let detail = refused.detail.expect("a sentence");
    assert!(detail.contains(&format!("127.0.0.1:{port}")), "{detail}");
    assert!(detail.contains("nothing was filed"), "{detail}");
    assert_eq!(telemetry.reports().expect("nothing kept").len(), 0);
}

#[test]
fn an_address_that_is_not_support_is_named() {
    let mut case = Case::new("support-elsewhere");
    let real = collector();
    let elsewhere = format!(
        "{}/robots.txt",
        &real[..real.find("/api/").expect("the collector address has the /api/ path")]
    );
    std::env::set_var("WISENT_SUPPORT_URL", &elsewhere);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&report("something failed"))
        .expect_err("the answer is not support's");
    case.note("refusal", json!(refused.detail));
    let remedy = refused.remedy.expect("a fix");
    assert!(remedy.contains(&elsewhere), "{remedy}");
    assert!(remedy.contains("/v1/public/reports"), "{remedy}");
}
