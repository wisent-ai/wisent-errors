//! Support reports against a real support service, wisent-customer-support,
//! named by `WISENT_SUPPORT_TEST_URL` (its `/v1/public/reports`). The agent
//! lists tickets and replies with `WISENT_SUPPORT_TEST_AGENT_TOKEN`, the
//! support-agent token the service holds under its own grant
//! (`SUPPORT_AGENT_TOKEN`, whose role carries the `reply` capability); the
//! service token is refused a reply (403 `Missing capability: reply`).

use serde_json::{json, Value};
use wisent_errors::telemetry::{Level, Report, PUBLIC_SUPPORT};

use crate::{collector, sample_failure, Case};

fn support() -> String {
    std::env::var("WISENT_SUPPORT_TEST_URL").expect(
        "set WISENT_SUPPORT_TEST_URL to a support service's /v1/public/reports: these cases run against a real one",
    )
}

fn token() -> String {
    std::env::var("WISENT_SUPPORT_TEST_AGENT_TOKEN").expect(
        "set WISENT_SUPPORT_TEST_AGENT_TOKEN to that service's support-agent token (its SUPPORT_AGENT_TOKEN, which carries the reply capability; the service token is refused a reply)",
    )
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
    assert_eq!(
        read.pointer("/replies/0/text").and_then(serde_json::Value::as_str),
        Some("Fixed in the next release.")
    );
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
    assert_eq!(
        refused.detail.as_deref(),
        Some("filing a support report: the report has no description; observed: the description is empty")
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some("say what you were doing and what happened: in an app's Report a Problem window, or with `wisent-errors-test support report --description \"…\"`")
    );
    assert!(telemetry.reports().expect("nothing kept").is_empty());
}

#[test]
fn a_plain_http_support_address_is_refused_by_name() {
    let mut case = Case::new("support-plain-http");
    let address = "http://support.example.invalid/v1/public/reports";
    std::env::set_var("WISENT_SUPPORT_URL", address);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&report("something failed"))
        .expect_err("plain http to another host is refused");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "config");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!("reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds {address}").as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some("set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it")
    );
    assert!(telemetry.reports().expect("nothing kept").is_empty());
    std::env::remove_var("WISENT_SUPPORT_URL");
    assert_eq!(
        telemetry.support_address().expect("the public one"),
        (PUBLIC_SUPPORT.to_owned(), "wisent-errors")
    );
}

#[test]
fn a_report_support_refuses_says_why() {
    let mut case = Case::new("support-refused");
    let address = support();
    std::env::set_var("WISENT_SUPPORT_URL", &address);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&Report {
            email: Some("not an address"),
            ..report("something failed")
        })
        .expect_err("support refuses the email");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "refused");
    assert_eq!(
        refused.detail.as_deref(),
        Some(format!("filing a support report at {address}: support refused HTTP 400: email \"not an address\" is not an email address; observed: nothing was filed").as_str())
    );
    assert_eq!(
        refused.remedy.as_deref(),
        Some("the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `wisent-errors-test support report`")
    );
    assert!(!refused.context.contains_key("wisent_errors.unfilled"), "{:?}", refused.context);
    assert!(telemetry.reports().expect("nothing kept").is_empty());
}

/// The discard port on loopback, where nothing listens on a host that runs
/// no discard service: https://www.rfc-editor.org/rfc/rfc863
const NOTHING_LISTENS: &str = "http://127.0.0.1:9/v1/public/reports";

#[test]
fn an_unreachable_support_files_nothing() {
    let mut case = Case::new("support-unreachable");
    std::env::set_var("WISENT_SUPPORT_URL", NOTHING_LISTENS);
    let telemetry = case.telemetry("wisent-errors-test-cli");
    let refused = telemetry
        .file_report(&report("something failed"))
        .expect_err("nothing answers");
    case.note("refusal", json!(refused.detail));
    assert_eq!(refused.code.as_str(), "infra_down");
    let detail = refused.detail.as_deref().expect("a sentence");
    let why = detail
        .strip_prefix(&format!("filing a support report at {NOTHING_LISTENS}: support could not be reached: "))
        .and_then(|rest| rest.strip_suffix("; observed: nothing was filed"))
        .unwrap_or_else(|| panic!("{detail}"));
    assert!(why.contains("Connection refused"), "the transport's own words: {why}");
    assert_eq!(
        refused.remedy.as_deref(),
        Some("send the report again once the network or support is back, from an app's Report a Problem window or with `wisent-errors-test support report`")
    );
    assert!(telemetry.reports().expect("nothing kept").is_empty());
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
    assert_eq!(refused.code.as_str(), "infra_down");
    let detail = refused.detail.as_deref().expect("a sentence");
    let (_answer, status) = detail
        .strip_prefix(&format!("reading support's answer at {elsewhere}: the answer is not a support service's: "))
        .and_then(|rest| rest.rsplit_once("; observed: HTTP "))
        .unwrap_or_else(|| panic!("{detail}"));
    assert!(status.parse::<u16>().is_ok(), "an HTTP status: {detail}");
    assert_eq!(
        refused.remedy.as_deref(),
        Some(format!("check that {elsewhere} is a support service's /v1/public/reports").as_str())
    );
    assert!(telemetry.reports().expect("nothing kept").is_empty());
}
