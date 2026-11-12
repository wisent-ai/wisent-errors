# Telemetry from installed copies

The `telemetry` feature of the Rust crate lets an installed product tell its
maintainers what failed on a user's machine, with the user's consent, without
any secret in the product and without ever getting in the user's way. It sends
to the first-party app collector Echo already serves for apps
(`POST /api/analytics/mobile/collect`), so a desktop or command-line product's
events land beside the web and mobile ones.

```toml
wisent-errors = { git = "https://github.com/wisent-ai/wisent-errors", rev = "<sha>", features = ["telemetry"] }
```

```rust
use wisent_errors::telemetry::{Product, Telemetry};

let telemetry = Telemetry::new(Product {
    id: "ster",
    app_id: "ster-cli",
    version: env!("CARGO_PKG_VERSION"),
});
telemetry.failure(&failure, Some("pairs-unreadable"));
telemetry.command("pairs import", 1, elapsed);
```

## Consent

Nothing is sent until the user answers. A product asks once, on a terminal it
is attached to (`Telemetry::ask`, which does nothing when stdin or stderr is
not a terminal, so a script or a coding agent is never prompted), or the user
answers with the product's own command (`<product> telemetry on|off`).

| level | what is sent |
|---|---|
| unanswered | nothing; events are not even queued |
| `off` | nothing |
| `errors` | failures only |
| `usage` | failures and the commands that ran, with their exit status and duration, never their arguments |

`DO_NOT_TRACK=1` turns every level off, whatever was answered.

## What is sent

Every event is the body the collector takes: `eventId`, `appId`, `platform`
(`macos` or `linux`), `eventName`, `anonymousId` (the installation's random id,
created on its first queued event), `sessionId` (one per process),
`appVersion`, `osVersion`, `occurredAt` and `properties`.

Every kind of event is declared once, in `telemetry::EVENTS`: its name, the
least consent under which it is queued, one sentence saying what it says, and
every key of its `properties`. The queue takes only a declared event, so an
event the catalogue does not list cannot be sent, and a product's privacy page
shows this catalogue. A `failure` carries the envelope's `failure_point`,
`error_code`, `severity`, `retryable`, `outage`, `service`, `impact`, `detail`
and `remedy`, the declared cause's id as `cause_id` when the product knows it,
its `context`, and the chain of causes underneath as `causes`. A `cli.command`
carries `command`, `exit_status` and `duration_ms`. The frustration signals are
below.

Before an event is queued, every text field is cleaned: the user's home
directory becomes `~` and the machine's host name becomes `<this-host>`. What
is in the queue is exactly what will be sent; `<product> telemetry show`
prints it.

## Frustration signals

The reporter counts three signals only the client sees, because they depend on
the order of what happened:

| event | when | consent | `properties` |
|---|---|---|---|
| `frustration.repeat_failure` | a failure has the same `failure_point` as the failure before it | `errors` | `failure_point`, `consecutive`, `seconds_since_previous` |
| `frustration.usage_loop` | a command is refused as usage (exit 2) and the usage refusal before it was the same command | `usage` | `command`, `consecutive`, `seconds_since_previous` |
| `frustration.help_after_failure` | the product calls `Telemetry::help(command)` when the user asks for help (`--help`, `help`, a Help menu) and a failure was recorded before | `usage` | `command`, `failure_point` of the last failure, `seconds_since_failure` |

A repeat is a second occurrence, so `consecutive` starts at 2 and grows with
each further repeat; a different failure, or the same command run without a
usage refusal, ends the run. No threshold is applied here: how many repeats in
how short a time make an alarm, or the one question that offers a support
report, is the operator's number, read by Echo. What was seen last is kept in
`signals.json` beside the queue, and only under the consent its signal needs.

## Where it lives

`$WISENT_TELEMETRY_HOME`, else `$XDG_STATE_HOME/<product>/telemetry`, else
`~/.local/state/<product>/telemetry`, the same root a product's onboarding
state uses:

| file | holds |
|---|---|
| `consent.json` | the level the user chose and when |
| `installation.json` | the installation's random id |
| `queue/<event-id>.json` | one event waiting to be sent |
| `delivery.json` | the last delivery attempt: when, how many were sent, and the refusal or transport error that stopped it |

## The collector address

Every product sends to Wisent's public collector,
`https://telemetry.wisent.com/api/analytics/mobile/collect`
(`telemetry::PUBLIC_COLLECTOR`, `WisentTelemetry.publicCollector`), the same
in a release and in a copy built from source. `WISENT_TELEMETRY_COLLECTOR_URL`
at run time names another one, which is how a self-hosted Echo or a test
collector is reached. An address that is not `https://` (or `http://` on a
loopback host) is refused by name, and the events wait. Nothing goes anywhere
until the user chose a level that sends it.

## Delivery

`Telemetry::flush` sends every queued event and removes each one the collector
accepted (`{"ok": true}`). It stops at the first refusal or transport error and
records it in `delivery.json`, so the events wait for the next attempt.
A command-line product never sends on the user's path: when its command ends
with events queued it starts itself again detached (`<product> telemetry
flush`, `Telemetry::spawn_flush`) and exits at once. A failure to queue or to
start the flush is said on stderr once, starting with `wisent-errors:`, and
never changes the product's own result or exit status.

## Status

`Telemetry::status` answers, as JSON a product prints for `<product> telemetry
status`:

```json
{
  "product": "ster",
  "app_id": "ster-cli",
  "level": "errors",
  "do_not_track": false,
  "collector": "https://…/api/analytics/mobile/collect",
  "collector_source": "wisent-errors",
  "installation": "1f0c…",
  "queued": 0,
  "last_delivery": { "at": "…", "sent": 1, "stopped": null },
  "directory": "~/.local/state/ster/telemetry"
}
```

`collector` is `null` with `collector_source` saying why (`none`: neither the
build nor `WISENT_TELEMETRY_COLLECTOR_URL` names one). `last_delivery.stopped`
is the collector's own sentence for a refusal (`the collector refused HTTP 403:
{"error":"Unknown mobile analytics app"}`), the transport error, or, for an
answer of HTTP 500 and above, the collector's own failure (`the collector failed
on its own side, HTTP 500: …`): such an event is not refused, nothing on the
sending machine is to fix, and it goes out again on the next flush.

## How each operation fails

`telemetry::operations()` declares every cause in the crate's own
`Operation` catalogue, each with its test under `tests/telemetry/`.

## Test

`kompilator test --manifest-path rust/Cargo.toml --features telemetry --test telemetry` runs
consent, cleaning, queueing and refusal against the real Echo collector named
by `WISENT_TELEMETRY_TEST_COLLECTOR`; with `WISENT_TELEMETRY_TEST_APP_ID` set
to an app the collector declares, it also checks the event is accepted, and
`WISENT_TELEMETRY_TEST_FAILING_COLLECTOR` names a collector deployment that
answers with a server error (an Echo that cannot reach its database) for the
case that keeps events through the collector's own failure.
Every run writes its source revision, the collector, each attempt and the
final state of the store under `.build/telemetry/<run>/report.json`.
