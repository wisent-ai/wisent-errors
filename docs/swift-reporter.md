# The Swift reporter

`WisentFailureReporter` reports an app's failures through its telemetry,
`WisentTelemetry`: the same contract, files and event shape as the Rust crate's
`telemetry` feature ([telemetry.md](telemetry.md)), so a product's command line
and its app share one consent, one installation id and one queue under
`$XDG_STATE_HOME/<product>/telemetry` (else `~/.local/state/<product>/telemetry`;
`WISENT_TELEMETRY_HOME` names another). One rule carries it: reporting never
fails the caller.

```swift
import WisentErrors

let refused = try Failure(failurePoint: "ster.backend-start", code: .config, service: "ster")
    .detail(providerText)

// Never throws, never blocks: the event is queued when the user agreed to
// send errors, and sent to the collector on a detached task.
WisentFailureReporter.shared.report(refused)

// A process about to exit awaits the attempt instead of guessing how long it
// needs: `settled` runs once it ended, and at once when nothing was queued.
await withCheckedContinuation { (settled: CheckedContinuation<Void, Never>) in
    WisentFailureReporter.shared.report(refused) { settled.resume() }
}
```

## Which product reports

The app's Info.plist declares it:

| key | holds |
|---|---|
| `WisentTelemetryProduct` | the product id, the directory its state lives under (`ster`) |
| `WisentTelemetryAppID` | the app Echo's collector declares in its `MOBILE_ANALYTICS_APPS_JSON` (`ster-desktop`) |

An app whose Info.plist lacks either reports nothing and says once on stderr
`wisent-errors: telemetry: this app's Info.plist declares no <key>, so it
reports no failure`. Events go to Wisent's public collector unless
`WISENT_TELEMETRY_COLLECTOR_URL` in the environment names another
([telemetry.md](telemetry.md#the-collector-address)).

## Consent and settings

Nothing is queued until the user answers, in the app or with the product's
command line. `WisentTelemetry` gives an app's settings screen what the command
line gives a terminal: `level()` and `setLevel(_:)` (`off`, `errors`, `usage`;
`off` drops what waits), `queued()` (every waiting event exactly as it will be
sent), `flush()` (what it sent, what remains, and why it stopped) and
`status()` (the same fields as `<product> telemetry status`). `DO_NOT_TRACK=1`
sends nothing.

The `WisentTelemetryUI` product is that screen, so no app writes its own: an
app adds it to its `Settings` scene with
`TelemetrySettingsView(productName: "Jeden", telemetry: WisentFailureReporter.shared.telemetry)`.
It shows the choice (with "Not answered yet" until there is one), how many
events wait, where they go and when they last went, the waiting events
exactly as they will be sent, and Send now with what it sent or why nothing
went. An app whose Info.plist declares no product shows that it reports
nothing.

## What is said on stderr

Every sentence starts with `wisent-errors: telemetry:` and is the sentence the
command line prints for the same cause: a directory that cannot be written, a
state file telemetry did not write, a collector address that is not https (or
http on the loopback), the collector's refusal with its own answer, an answer
from an address that is not the collector, and a collector that could not be
reached. The events stay queued in every case but the first.

## Test

`swift test` runs `tests/telemetry/swift` against the real collector named by
`WISENT_TELEMETRY_TEST_COLLECTOR`; without it the delivery case is skipped as
blocked, never passed.
