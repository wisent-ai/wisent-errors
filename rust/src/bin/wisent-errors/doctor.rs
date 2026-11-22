//! `wisent-errors doctor`: every functionality this command runs, tried now
//! for the product the product file names, each said as working with what
//! was seen, failing with what failed and its fix, or not tried and why
//! (docs/diagnosis.md). Nothing is sent: the collector and support are
//! named, not written to, and no report is filed.

use std::process::ExitCode;
use std::sync::OnceLock;

use serde_json::{Map, Value};
use wisent_errors::cli_output::read_json;
use wisent_errors::diagnosis::{self, Check, Probe};
use wisent_errors::failures as own;
use wisent_errors::telemetry::{Product, Telemetry};
use wisent_errors::Failure;

use crate::say;

/// The product the doctor speaks for and its file: a probe is a plain `fn`,
/// so what it tries is kept here for the run.
static GIVEN: OnceLock<(Product, String)> = OnceLock::new();

fn given() -> &'static (Product, String) {
    GIVEN.get().expect("the doctor keeps its product before any probe runs")
}

fn telemetry() -> Telemetry {
    Telemetry::new(given().0)
}

/// The product file still reads, as every command of the product reads it.
fn product_file() -> Result<String, Failure> {
    let (product, path) = given();
    match read_json::<Map<String, Value>>(path) {
        Ok(_) => Ok(format!("{path} names {} {}, app {}", product.id, product.version, product.app_id)),
        Err(refused) => {
            let values = refused.values();
            let borrowed: Vec<(&str, &str)> = values.iter().map(|(key, value)| (*key, value.as_str())).collect();
            Err(refused.cause().failure(own::COMMAND_PRODUCT.id, product.id, &borrowed))
        }
    }
}

/// The user's answer reads back.
fn consent() -> Result<String, Failure> {
    let answered = match telemetry().level()? {
        Some(level) => format!("the user chose {}", level.as_str()),
        None => "the user has not answered, so nothing is queued or sent".to_owned(),
    };
    Ok(match Telemetry::do_not_track() {
        true => format!("{answered}; DO_NOT_TRACK turns every level off"),
        false => answered,
    })
}

/// The queue reads back.
fn record() -> Result<String, Failure> {
    let queued = telemetry().queued()?.len();
    Ok(format!("{queued} event(s) wait to be sent"))
}

/// The telemetry directory can be written.
fn store() -> Result<String, Failure> {
    telemetry().check_writable()
}

/// The collector address is one events may go to.
fn deliver() -> Result<String, Failure> {
    let collector = telemetry().collector()?;
    Ok(format!("events go to {}, named by {}", collector.url, collector.source))
}

/// Every report filed from this installation reads back from support.
fn status() -> Result<String, Failure> {
    let reports = telemetry().reports()?;
    if reports.is_empty() {
        return Ok("no report was filed from this installation".to_owned());
    }
    let read = reports.iter().filter(|report| report.get("unread").is_none()).count();
    Ok(format!("{} report(s) filed from this installation, {read} read back from support", reports.len()))
}

/// The support address is one reports may go to.
fn exchange() -> Result<String, Failure> {
    let (address, source) = telemetry().support_address()?;
    Ok(format!("reports go to {address}, named by {source}"))
}

/// One check per functionality `errors list` declares, in the order the
/// doctor says them; `doctor check` holds them to that listing.
fn checks() -> [Check; 15] {
    [
        Check { operation: &own::COMMAND_ARGUMENTS, probe: Probe::Skipped("it read this command line to start the diagnosis") },
        Check { operation: &own::COMMAND_PRODUCT, probe: Probe::Run(product_file) },
        Check { operation: &own::CLI_OUTPUT_READ_JSON, probe: Probe::Skipped("the product file is read through it, so the product file's line says whether it works") },
        Check { operation: &own::TELEMETRY_CONSENT, probe: Probe::Run(consent) },
        Check { operation: &own::TELEMETRY_RECORD, probe: Probe::Run(record) },
        Check { operation: &own::TELEMETRY_STORE, probe: Probe::Run(store) },
        Check { operation: &own::TELEMETRY_DELIVER, probe: Probe::Run(deliver) },
        Check { operation: &own::TELEMETRY_EXPORT, probe: Probe::Skipped("it writes a file the user names, so only `telemetry export` writes one") },
        Check { operation: &own::ENVELOPE_BUILD, probe: Probe::Skipped("it builds the envelope of a failure a product reports, so only `telemetry failure` builds one") },
        Check { operation: &own::SUPPORT_REPORT, probe: Probe::Skipped("it files a report a person at support reads, so only `support report` files one") },
        Check { operation: &own::SUPPORT_STATUS, probe: Probe::Run(status) },
        Check { operation: &own::SUPPORT_EXCHANGE, probe: Probe::Run(exchange) },
        Check { operation: &own::COMMAND_CHECK, probe: Probe::Skipped("it reads the files a product's CI names, so only `doctor check` and `warnings check` read them") },
        Check { operation: &own::CLI_OUTPUT_DIAGNOSE, probe: Probe::Skipped("it is this diagnosis, which says a probe that fails without saying why in that probe's own line") },
        Check { operation: &own::CLI_OUTPUT_PRINT, probe: Probe::Skipped("the diagnosis is printed through it, so a standard output it cannot write is this command's own refusal") },
    ]
}

/// Try every check for `product`, read from `path`, and print the findings:
/// one line each, or with `json` the array. Exits 0 when nothing failed and
/// 1 when a functionality failed.
pub fn run(product: Product, path: String, json: bool, text: bool) -> ExitCode {
    // discarded: the doctor runs once per process, so the cell is empty here; a second run would keep the first product.
    let _ = GIVEN.set((product, path));
    let findings = diagnosis::diagnose(&checks());
    let printed = match json {
        true => say::print(&diagnosis::to_json(&findings), text),
        false => say::print_text(&diagnosis::render(&findings)),
    };
    match printed == ExitCode::SUCCESS {
        true => say::exit(diagnosis::exit_status(&findings)),
        false => printed,
    }
}
