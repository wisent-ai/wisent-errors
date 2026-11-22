//! `wisent-errors --product <file> support report` and `support status`:
//! a report filed with the real support service, its key kept in the
//! product's telemetry directory, and support's reply read back.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry support::
//!
//! - Rule 4: both commands run as the crate's command line, a process
//!   (`Case::run`, main.rs), against the real support service,
//!   wisent-customer-support, named by `WISENT_SUPPORT_TEST_URL` (its
//!   `/v1/public/reports`) and given to the command as its own
//!   `WISENT_SUPPORT_URL`. The only requests this file makes itself are a
//!   support agent's, the other side of the real flow: listing the tickets
//!   and replying with `WISENT_SUPPORT_TEST_AGENT_TOKEN`, the support-agent
//!   token the service holds under its own grant (`SUPPORT_AGENT_TOKEN`,
//!   whose role carries the `reply` capability), read from the environment
//!   and sent in a header, never on a command line. A case that needs the
//!   service, the token or the collector's origin and is not given it fails
//!   with `blocked:` naming the variable; what is refused before anything
//!   is sent needs none of them. The cases are split by the real component
//!   each one needs, so a gate host without the service still runs the
//!   refusals that need nothing.
//!
//! After every step a case reads back the exit status, the whole refusal,
//! and the `support/` directory where the command keeps each report's key:
//! nothing is kept for a report that was not filed, and `support status`
//! leaves each kept key as it was. What support and the transport say in
//! their own words is the one part of a sentence read only as part; the
//! rest of every sentence is its catalogue template rendered whole with the
//! values the case observes, as the command could not be built where these
//! cases were written.

use serde_json::{json, Value};

use crate::{between, cause, elsewhere, refusal, Case, FAILURE, NOTHING_LISTENS, PRODUCT, RETRY, USAGE};

fn support() -> String {
    match std::env::var("WISENT_SUPPORT_TEST_URL") {
        Ok(address) => address,
        Err(error) => panic!("blocked: WISENT_SUPPORT_TEST_URL names no support service ({error}); set it to a support service's /v1/public/reports: these cases run against a real one"),
    }
}

fn token() -> String {
    match std::env::var("WISENT_SUPPORT_TEST_AGENT_TOKEN") {
        Ok(token) => token,
        Err(error) => panic!(
            "blocked: WISENT_SUPPORT_TEST_AGENT_TOKEN is not set ({error}); set it to that service's support-agent token (its SUPPORT_AGENT_TOKEN, which carries the reply capability; the service token is refused a reply)"
        ),
    }
}

/// The service's own API, as a support agent uses it.
fn agent(path: &str) -> String {
    let base = support();
    let origin = &base[..base.find("/v1/").expect("the address has the /v1/ path")];
    format!("{origin}{path}")
}

/// What `support report` sends besides its description.
const SUBJECT: [&str; 2] = ["--subject", "pairs import fails"];

/// A refusal whose first line is `prefix`, the words of support or the
/// transport, then `suffix`, followed by exactly `rest`; the middle part,
/// which it returns, is read only as part.
fn refused_around(ran: &crate::Ran, status: i32, prefix: &str, suffix: &str, rest: &[String]) -> String {
    let said = ran.said();
    assert_eq!((ran.status, said.len(), ran.stdout.as_str()), (status, rest.len() + 1, ""), "{said:?}");
    assert_eq!(&said[1..], rest, "{said:?}");
    between(&said[0], prefix, suffix).to_owned()
}

/// `support report` without a description, with `--description` as the
/// last word, to a plain-http support address and to an address where
/// nothing listens: refused before anything is filed, nothing kept.
#[test]
fn support_report_refuses_what_it_cannot_file_before_anything_is_kept() {
    let mut case = Case::new("support-refusals");

    for words in [&["support", "report"][..], &["support", "report", "--description", "   "][..]] {
        case.run(words).refused(USAGE, &refusal(
            "filing a support report: the report has no description; observed: the description is empty",
            &format!("say what you were doing and what happened: in an app's Report a Problem window, or with `{PRODUCT} support report --description \"…\"`"),
            "wisent-errors.support.report", "support-description-empty", "telemetry",
        ));
    }
    case.run(&["support", "report", "--description"]).refused(USAGE, &refusal(
        "reading the option --description: the option takes a value and is the last word of the command line; observed: the arguments were [\"--product\",\"PRODUCT_FILE\",\"support\",\"report\",\"--description\"]"
            .replace("PRODUCT_FILE", &case.product.display().to_string())
            .as_str(),
        "give its value right after it, as in `--description <text>`",
        "wisent_errors.command.arguments", "option-value-missing", "command",
    ));
    assert!(!case.state.exists(), "nothing is kept for a report refused by its words");

    let address = "http://support.example.invalid/v1/public/reports";
    case.set("WISENT_SUPPORT_URL", address);
    case.run(&["support", "report", "--description", "something failed"]).refused(FAILURE, &refusal(
        &format!("reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds {address}"),
        "set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it",
        "wisent-errors.support.exchange", "support-address-invalid", "telemetry",
    ));
    assert!(!case.state.exists(), "nothing is kept for a report to a refused address");

    let nothing = format!("{NOTHING_LISTENS}/v1/public/reports");
    case.set("WISENT_SUPPORT_URL", nothing.as_str());
    let ran = case.run(&["support", "report", "--description", "something failed"]);
    let why = refused_around(
        &ran,
        RETRY,
        &format!("Error: filing a support report at {nothing}: support could not be reached: "),
        "; observed: nothing was filed",
        &[
            format!("fix: send the report again once the network or support is back, from an app's Report a Problem window or with `{PRODUCT} support report`"),
            cause("wisent-errors.support.exchange", "support-unreachable", "telemetry"),
        ],
    );
    assert!(why.contains("Connection refused"), "the transport's own words: {why}");
    assert!(!case.holds("support"), "nothing is kept for a report that was not filed");
}

/// `support report` to the real support: refused for an email support does
/// not take, then filed with the newest failure, its key kept on disk.
#[test]
fn support_report_files_with_the_real_support_and_keeps_its_key() {
    let mut case = Case::new("support-report");
    let address = support();
    case.set("WISENT_SUPPORT_URL", address.as_str());

    let mut words = vec!["support", "report", "--description", "something failed", "--email", "not an address"];
    words.extend(SUBJECT);
    case.run(&words).refused(FAILURE, &refusal(
        &format!("filing a support report at {address}: support refused HTTP 400: email \"not an address\" is not an email address; observed: nothing was filed"),
        &format!("the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `{PRODUCT} support report`"),
        "wisent-errors.support.exchange", "support-refused", "telemetry",
    ));
    assert!(!case.holds("support"), "nothing is kept for a refused report");

    case.run(&["telemetry", "level", "errors"]).succeeded();
    case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found", "--cause-id", "pairs-unreadable"]).succeeded();
    let mut words = vec!["support", "report", "--description", "example-product pairs import stops on a file that opens fine", "--with-failure"];
    words.extend(SUBJECT);
    let filed = case.run(&words).succeeded();
    let id = filed["id"].as_str().expect("support's id of the report").to_owned();
    let kept_path = case.state.join("support").join(format!("{id}.json"));
    assert_eq!(
        (&filed["address"], &filed["kept"], &filed["with_failure"]),
        (&json!(address), &json!(kept_path.display().to_string()), &json!(true))
    );
    let kept = case.json(&format!("support/{id}.json"));
    assert_eq!((&kept["id"], &kept["address"], &kept["subject"]), (&json!(id), &json!(address), &json!("pairs import fails")));
    assert!(kept["access_key"].as_str().is_some_and(|key| key.len() >= 40), "the access key is kept: {kept}");
    assert_eq!(case.queued().len(), 1, "filing a report leaves the queue as it was");
}

/// `support report` to an address that answers and is not support.
#[test]
fn support_report_names_an_address_that_is_not_support() {
    let mut case = Case::new("support-elsewhere");
    let address = elsewhere("/robots.txt");
    case.set("WISENT_SUPPORT_URL", address.as_str());
    let ran = case.run(&["support", "report", "--description", "something failed"]);
    let said = ran.said();
    assert_eq!((ran.status, said.len(), ran.stdout.as_str()), (RETRY, 3, ""), "{said:?}");
    let rest = between(&said[0], &format!("Error: reading support's answer at {address}: the answer is not a support service's: "), "");
    let Some((_answer, status)) = rest.rsplit_once("; observed: HTTP ") else {
        panic!("no HTTP status: {said:?}");
    };
    assert!(status.parse::<u16>().is_ok(), "an HTTP status: {said:?}");
    assert_eq!(
        &said[1..],
        [
            format!("fix: check that {address} is a support service's /v1/public/reports"),
            cause("wisent-errors.support.exchange", "support-answer-unreadable", "telemetry"),
        ]
    );
    assert!(!case.holds("support"), "nothing is kept for a report that was not filed");
}

/// `support status` with nothing filed and with an operand it does not
/// take; then, once a report is filed and a support agent replied, the
/// reply read back, every kept key left as it was.
#[test]
fn support_status_reads_back_what_support_answered() {
    let mut case = Case::new("support-status");
    let address = support();
    case.set("WISENT_SUPPORT_URL", address.as_str());

    assert_eq!(case.run(&["support", "status"]).succeeded(), json!([]));
    case.run(&["support", "status", "now"]).refused(USAGE, &refusal(
        "reading the operands of `wisent-errors support status`: the command takes no operand, and \"now\" is more than it reads; observed: its operands were [\"now\"]",
        "drop \"now\", or quote an operand that holds spaces as one word, as in `wisent-errors --product <file> support status`",
        "wisent_errors.command.arguments", "operand-extra", "command",
    ));
    assert!(!case.state.exists(), "status keeps nothing of its own");

    case.run(&["telemetry", "level", "errors"]).succeeded();
    case.run(&["telemetry", "failure", "example-product.pairs.import", "not_found", "--cause-id", "pairs-unreadable"]).succeeded();
    let mut words = vec!["support", "report", "--description", "example-product pairs import stops on a file that opens fine", "--with-failure"];
    words.extend(SUBJECT);
    let id = case.run(&words).succeeded()["id"].as_str().expect("support's id of the report").to_owned();
    let kept = case.read(&format!("support/{id}.json"));

    // The support agent's side: the ticket carries the installation's report.
    let listed = ureq::get(&agent("/v1/support/tickets"))
        .set("x-support-token", &token())
        .call()
        .expect("the agent lists tickets")
        .into_string()
        .expect("the answer");
    let tickets: Value = serde_json::from_str(&listed).expect("the tickets are JSON");
    let ticket = tickets
        .as_array()
        .expect("a list")
        .iter()
        .find(|ticket| ticket["public_id"] == id.as_str())
        .expect("the report is a ticket")
        .clone();
    let report = &ticket["metadata"]["installation_report"];
    assert_eq!((&report["product"], &report["failure"]["cause_id"]), (&json!(PRODUCT), &json!("pairs-unreadable")));
    assert_eq!(report["installation"], case.json("installation.json")["id"], "the report names this installation");
    ureq::post(&agent(&format!("/v1/support/tickets/{}/reply", ticket["id"].as_str().expect("the ticket id"))))
        .set("x-support-token", &token())
        .set("content-type", "application/json")
        .send_string(&json!({ "body_text": "Fixed in the next release." }).to_string())
        .expect("the agent replies");

    let reports = case.run(&["support", "status"]).succeeded();
    let Some(read) = reports.as_array().expect("a list").iter().find(|read| read["id"] == id.as_str()) else {
        panic!("the report reads back: {reports}");
    };
    assert_eq!(read["status"], "waiting_on_customer");
    assert_eq!(read.pointer("/replies/0/text"), Some(&json!("Fixed in the next release.")));
    assert_eq!(case.read(&format!("support/{id}.json")), kept, "status leaves the kept key as it was");
}
