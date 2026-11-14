//! Support reports filed from an installed product: `<product> support report`
//! files one with this installation's id and, when asked, its newest queued
//! failure; `<product> support status` reads each back with the key it was
//! filed with. The contract is docs/support.md.

use std::path::PathBuf;

use serde_json::{json, Value};

use super::causes::{
    DESCRIPTION_EMPTY, SUPPORT_ADDRESS_INVALID, SUPPORT_ANSWER_UNREADABLE, SUPPORT_REFUSED,
    SUPPORT_UNREACHABLE,
};
use super::{acceptable_collector, store, Telemetry};
use crate::Failure;

/// The public address Wisent's support takes reports on. Every product files
/// here unless `WISENT_SUPPORT_URL` names another support service.
pub const PUBLIC_SUPPORT: &str = "https://support.wisent.com/v1/public/reports";

const RUNTIME_SUPPORT: &str = "WISENT_SUPPORT_URL";
const REPORT_POINT: &str = "wisent-errors.support.report";
const STATUS_POINT: &str = "wisent-errors.support.status";

/// What the user writes when filing a report.
#[derive(Clone, Copy, Debug, Default)]
pub struct Report<'a> {
    pub subject: Option<&'a str>,
    pub description: &'a str,
    pub email: Option<&'a str>,
    /// Attach the newest failure waiting in the telemetry queue.
    pub with_failure: bool,
}

impl Telemetry {
    /// The support address and what named it: `WISENT_SUPPORT_URL`, or
    /// `wisent-errors` for Wisent's public support.
    pub fn support_address(&self) -> Result<(String, &'static str), Failure> {
        let runtime = std::env::var(RUNTIME_SUPPORT)
            .ok()
            .map(|value| value.trim().trim_end_matches('/').to_owned())
            .filter(|value| !value.is_empty());
        let Some(address) = runtime else {
            return Ok((PUBLIC_SUPPORT.to_owned(), "wisent-errors"));
        };
        if acceptable_collector(&address) {
            Ok((address, RUNTIME_SUPPORT))
        } else {
            Err(SUPPORT_ADDRESS_INVALID.failure(
                REPORT_POINT,
                self.product().id,
                &[("address", &address)],
            ))
        }
    }

    fn reports_directory(&self) -> Option<PathBuf> {
        self.file("support")
    }

    /// File one report and keep its id and access key under the telemetry
    /// directory, `support/<id>.json`. Answers what support answered, without
    /// the key.
    pub fn file_report(&self, report: &Report) -> Result<Value, Failure> {
        let product = self.product().id;
        let description = report.description.trim();
        if description.is_empty() {
            return Err(DESCRIPTION_EMPTY.failure(REPORT_POINT, product, &[("product", product)]));
        }
        let (address, _) = self.support_address()?;
        let directory = self
            .reports_directory()
            .ok_or_else(|| self.no_home("a support report"))?;
        let failure = if report.with_failure {
            self.newest_failure()?
        } else {
            Value::Null
        };
        let body = json!({
            "product": product,
            "app": self.product().app_id,
            "version": self.product().version,
            "os": store::os_version().unwrap_or_else(|| store::platform().to_owned()),
            "installation": self.installation()?,
            "subject": report.subject.map(str::trim).filter(|subject| !subject.is_empty()),
            "description": description,
            "email": report.email.map(str::trim).filter(|email| !email.is_empty()),
            "failure": failure,
        });
        let answer = exchange(
            ureq::post(&address).set("content-type", "application/json"),
            Some(&body),
            &address,
            "filing a support report",
            "nothing was filed",
            product,
            REPORT_POINT,
        )?;
        let (Some(id), Some(key)) = (
            answer.get("id").and_then(Value::as_str),
            answer.get("access_key").and_then(Value::as_str),
        ) else {
            return Err(SUPPORT_ANSWER_UNREADABLE.failure(
                REPORT_POINT,
                product,
                &[
                    ("address", &address),
                    ("answer", &answer.to_string()),
                    ("status", "201"),
                ],
            ));
        };
        let kept = directory.join(format!("{id}.json"));
        store::write_json(
            &kept,
            "a support report's key",
            &json!({
                "id": id,
                "access_key": key,
                "address": address,
                "subject": body["subject"],
                "filed_at": store::now(),
            }),
            product,
        )?;
        Ok(json!({
            "id": id,
            "status": answer.get("status"),
            "created_at": answer.get("created_at"),
            "address": address,
            "kept": kept.display().to_string(),
            "with_failure": !body["failure"].is_null(),
        }))
    }

    /// Every report this installation filed, oldest first, as support answers
    /// it now: `status`, `replies`, or the refusal that stopped the reading.
    pub fn reports(&self) -> Result<Vec<Value>, Failure> {
        let product = self.product().id;
        let Some(directory) = self.reports_directory() else {
            return Ok(Vec::new());
        };
        let entries = match std::fs::read_dir(&directory) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(self.unwritable("the support reports", &directory, &error)),
        };
        let mut kept = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            if let Some(report) = store::read_json(&path, "a support report's key", product, product)? {
                kept.push(report);
            }
        }
        kept.sort_by(|a, b| a["filed_at"].as_str().cmp(&b["filed_at"].as_str()));
        Ok(kept
            .into_iter()
            .map(|report| {
                let id = report["id"].as_str().unwrap_or_default();
                let address = report["address"].as_str().unwrap_or(PUBLIC_SUPPORT);
                let key = report["access_key"].as_str().unwrap_or_default();
                let url = format!("{address}/{id}");
                match exchange(
                    ureq::get(&url).set("authorization", &format!("Bearer {key}")),
                    None,
                    &url,
                    &format!("reading report {id}"),
                    "its state is unknown until support answers",
                    product,
                    STATUS_POINT,
                ) {
                    Ok(state) => state,
                    Err(failure) => json!({
                        "id": id,
                        "subject": report["subject"],
                        "unread": { "detail": failure.detail, "remedy": failure.remedy },
                    }),
                }
            })
            .collect())
    }

    /// The properties of the newest failure waiting in the queue, or null.
    fn newest_failure(&self) -> Result<Value, Failure> {
        let newest = self
            .queued()?
            .into_iter()
            .filter(|event| event["eventName"] == "failure")
            .max_by(|a, b| a["occurredAt"].as_str().cmp(&b["occurredAt"].as_str()));
        Ok(newest.map_or(Value::Null, |event| event["properties"].clone()))
    }
}

/// One request to support and its JSON answer, or the refusal that names
/// what was being done, at which address, and why it stopped.
fn exchange(
    request: ureq::Request,
    body: Option<&Value>,
    address: &str,
    doing: &str,
    observed: &str,
    product: &str,
    point: &str,
) -> Result<Value, Failure> {
    let answer = match body {
        Some(body) => request.send_string(&body.to_string()),
        None => request.call(),
    };
    let common = [("doing", doing), ("address", address), ("observed", observed)];
    match answer {
        Ok(response) => {
            let status = response.status().to_string();
            let text = response.into_string().unwrap_or_default();
            serde_json::from_str::<Value>(&text)
                .ok()
                .filter(Value::is_object)
                .ok_or_else(|| {
                    SUPPORT_ANSWER_UNREADABLE.failure(
                        point,
                        product,
                        &[("address", address), ("answer", &text), ("status", &status)],
                    )
                })
        }
        Err(ureq::Error::Status(status, response)) => {
            let text = response.into_string().unwrap_or_default();
            // Support refuses with {"error": {"message": …}}; anything else
            // came from an address that is not support.
            let said = serde_json::from_str::<Value>(&text)
                .ok()
                .and_then(|answer| answer["error"]["message"].as_str().map(str::to_owned)
                    .or_else(|| answer["error"]["code"].as_str().map(str::to_owned)));
            let status = status.to_string();
            match said {
                Some(reason) => {
                    let mut values = common.to_vec();
                    values.extend([("status", status.as_str()), ("answer", reason.as_str())]);
                    Err(SUPPORT_REFUSED.failure(point, product, &values))
                }
                None => Err(SUPPORT_ANSWER_UNREADABLE.failure(
                    point,
                    product,
                    &[("address", address), ("answer", &text), ("status", &status)],
                )),
            }
        }
        Err(ureq::Error::Transport(transport)) => {
            let error = transport.to_string();
            let mut values = common.to_vec();
            values.push(("why", error.as_str()));
            Err(SUPPORT_UNREACHABLE.failure(point, product, &values))
        }
    }
}
