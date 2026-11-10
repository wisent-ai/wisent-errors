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
    built_collector: option_env!("WISENT_TELEMETRY_COLLECTOR_URL"),
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

A `failure` carries the envelope's `failure_point`, `error_code`, `severity`,
`retryable`, `outage`, `service`, `detail` and `remedy`, the declared cause's
id as `cause_id` when the product knows it, and the chain of causes underneath
as `causes`. A `cli.command` carries `command`, `exit_status` and
`duration_ms`.

Before an event is queued, every text field is cleaned: the user's home
directory becomes `~` and the machine's host name becomes `<this-host>`. What
is in the queue is exactly what will be sent; `<product> telemetry show`
prints it.

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

The release build passes `WISENT_TELEMETRY_COLLECTOR_URL` at compile time, so
only our own release knows our collector; a copy built from source knows none.
The same variable at run time overrides it, which is how a self-hosted Echo or
a test collector is named. An address that is not `https://` (or `http://` on a
loopback host) is refused by name. Without an address events still queue, and
`<product> telemetry status` says no collector is known.

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
  "collector_source": "build",
  "installation": "1f0c…",
  "queued": 0,
  "last_delivery": { "at": "…", "sent": 1, "stopped": null },
  "directory": "~/.local/state/ster/telemetry"
}
```

`collector` is `null` with `collector_source` saying why (`none`: neither the
build nor `WISENT_TELEMETRY_COLLECTOR_URL` names one). `last_delivery.stopped`
is the collector's own sentence for a refusal (`the collector refused HTTP 403:
{"error":"Unknown mobile analytics app"}`) or the transport error.

## How each operation fails

`telemetry::operations()` declares every cause in the crate's own
`Operation` catalogue, each with its test under `tests/telemetry/`.

## Test

`cargo test -p wisent-errors --features telemetry --test telemetry` runs
consent, cleaning, queueing and refusal against the real Echo collector named
by `WISENT_TELEMETRY_TEST_COLLECTOR`; with `WISENT_TELEMETRY_TEST_APP_ID` set
to an app the collector declares, it also checks the event is accepted.
Every run writes its source revision, the collector, each attempt and the
final state of the store under `.build/telemetry/<run>/report.json`.
