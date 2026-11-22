# Support reports

How an installed product asks a person for help, with what support needs to
answer without asking back: the product, its version, the system, the
installation, and, when the user agrees, the failure it just had. A command
line files with `<product> support report` and reads replies with `<product>
support status`; an app does the same from Help → Report a Problem. The
service on the other side is `wisent-customer-support`
(`POST /v1/public/reports`, `GET /v1/public/reports/<id>`).

```rust
use wisent_errors::telemetry::{Product, Report, Telemetry};

let telemetry = Telemetry::new(Product { id: "ster", app_id: "ster-cli", version: env!("CARGO_PKG_VERSION") });
let filed = telemetry.file_report(&Report {
    subject: Some("pairs import fails"),
    description: "ster pairs import stops on a file that opens fine",
    email: None,
    with_failure: true,
})?;
let reports = telemetry.reports()?;
```

An app gets the same from `WisentTelemetry` (`fileReport(subject:description:email:withFailure:)`,
`reports()`, `supportAddress()`, with the same sentences as `SupportError`)
and the window from `WisentTelemetryUI`:

```swift
WisentSupportWindow(productName: "Jeden", telemetry: WisentFailureReporter.shared.telemetry)
// in .commands:
CommandGroup(after: .help) { WisentReportProblemCommand() }
```

Help → Report a Problem… opens it: subject, what happened, an optional email,
whether to attach the last failure, Send report, and every report this
installation filed with its status and replies.

## What is sent

`product`, `app`, `version`, `os` and `installation` (the id `<product>
telemetry status` prints, made on first use), the `subject` and `description`
the user wrote, the `email` only when the user gave one, and with
`with_failure` the newest failure waiting in the telemetry queue, exactly as
`<product> telemetry show` prints it, already cleaned of the home directory and
host name. A user who never agreed to telemetry has no queued failure, and the
report goes without one.

## Where it goes

Every product files with Wisent's public support,
`https://support.wisent.com/v1/public/reports`
(`telemetry::PUBLIC_SUPPORT`), unless `WISENT_SUPPORT_URL` names another
support service's `/v1/public/reports`. An address that is not `https://` (or
`http://` on a loopback host) is refused by name.

## What is kept

Support answers the report's id (`WCS-000042`) and an access key, the only way
to read the report back. Both are kept in `support/<id>.json` under the
telemetry directory (`$WISENT_TELEMETRY_HOME`, else
`$XDG_STATE_HOME/<product>/telemetry`, else `~/.local/state/<product>/telemetry`),
with the address it was filed at and when. `file_report` answers `id`,
`status`, `created_at`, `address`, `kept` and `with_failure`; the key is never
printed.

## Reading it back

`reports` answers every kept report, oldest first, as support answers it now:
`id`, `status` (`triaged`, `open`, `waiting_on_customer`, `resolved`, …),
`subject`, `created_at`, `updated_at` and `replies`, each `at` and `text`. A
report support could not be asked about answers `id`, `subject` and `unread`
with the sentence and the fix; the others still read.

## Refusals

| cause | when | sentence |
|---|---|---|
| `support-description-empty` | the description is empty | `filing a support report: the report has no description; fix: say what you were doing and what happened: <product> support report --description "…"` |
| `support-address-invalid` | `WISENT_SUPPORT_URL` is not https | `reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds <address>` |
| `support-refused` | support answered 4xx or 5xx with its reason | `<doing> at <address>: support refused HTTP <status>: <its reason>; observed: nothing was filed` — a 503 with reason `config` means the support deployment lacks a setting its operator must add |
| `support-unreachable` | no connection | `<doing> at <address>: support could not be reached: <error>; observed: nothing was filed` |
| `support-answer-unreadable` | the address answered something that is not support's JSON | `reading support's answer at <address>: the answer is not a support service's: <answer>; observed: HTTP <status>`, the answer on one line: JSON written again compactly, any other text quoted as a JSON string with its line ends escaped |

Keeping the key can fail as telemetry's store does (`store-unwritable`,
[telemetry.md](telemetry.md)). A key file `support status` cannot read as
the key filing kept is refused as `support-key-unreadable`, whose fix is to
remove that file and file the report again: filing keeps the new report's
key, and nothing else writes a key. Nothing is kept for a report support did
not take.

## Tests

`tests/telemetry/support.rs`, which runs `wisent-errors --product <file>
support report|status` ([command-line.md](command-line.md)) as a process, and
`tests/telemetry/swift/SupportReportTests.swift`, which runs `wisent-errors-swift
support report|status` ([swift-reporter.md](guides/swift-reporter.md#the-command-line-wisent-errors-swift))
the same way, run the cases against a real
`wisent-customer-support` named by `WISENT_SUPPORT_TEST_URL`; a case without
it fails naming the variable. The
agent lists tickets and replies through its API with
`WISENT_SUPPORT_TEST_AGENT_TOKEN`, the support-agent token the service holds
under its own grant (`SUPPORT_AGENT_TOKEN`), whose role carries the `reply`
capability; the service token is refused a reply with 403
`Missing capability: reply`, and a refused reply fails the case. What is
refused before anything is sent (`SupportRefusalTests`, and in Rust
`support_report_refuses_what_it_cannot_file_before_anything_is_kept`: no
description, a plain-http address, nothing listening on 127.0.0.1:9) needs
no service.
