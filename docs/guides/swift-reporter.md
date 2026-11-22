# The Swift reporter

`WisentFailureReporter` reports an app's failures through its telemetry,
`WisentTelemetry`: the same contract, files and event shape as the Rust crate's
`telemetry` feature ([telemetry.md](../telemetry.md)), so a product's command line
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
([telemetry.md](../telemetry.md#the-collector-address)).

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
http on the loopback), the collector's refusal with its own answer, the
collector's own failure (an answer of HTTP 500 and above, which names nothing
to fix on this machine), an answer from an address that is not the collector,
and a collector that could not be reached. The events stay queued in every
case but the first.

## Frustration signals

A failure with the same failure point as the one before it also queues
`frustration.repeat_failure`, with `consecutive` and `seconds_since_previous`,
exactly as the command line does ([telemetry](../telemetry.md#frustration-signals)).
The app and its command line keep one `signals.json`, so a failure in the app
and the same failure in the CLI count as one run. Usage refusals are a
command-line signal and are not counted here.

## Saying a failure to a person

An app shows a failure with `error.explained`, never `localizedDescription`:
a declared description as declared, a `DecodingError` with the coding path it
stopped at (`key "name" is missing at the top level`, `items.1 is not Int`), an
`EncodingError` with the value the encoder refused, its coding path and the
encoder's reason (`Double inf cannot be encoded at prices.1: Unable to encode
Double.infinity directly in JSON.`), a Cocoa error with its domain and code,
any other error as its type and value,
then each underlying error after `": "`, read until the chain ends or repeats.

JSON is read through the described calls, so the failure names what was being
read:

| call | throws | says |
|---|---|---|
| `JSONDecoder().decodeDescribed(T.self, from: data)` | `DescribedDecodingError` | `<T> could not be decoded: <reason>`, the reason `explained` gives |
| `JSONSerialization.describedObject(with: data)` | `DescribedJSONError` | the character and position where the text stopped being JSON |

`wisent-errors-swift envelope read` and `declaration check` (below) say every
file they cannot read this way; `swift test --filter "ExplainedTests|DescribedTests"`
runs their tests.

## The command line: `wisent-errors-swift`

The package's executable target drives the three libraries the way an app
drives them, so a product without an app, an operator at a terminal or a
product's CI uses them without writing Swift (`swift build --product
wisent-errors-swift`). Each refusal is a declared cause of
`catalogue/failures/swift-cli.json` (or the library's own, of
`envelope.json` and `telemetry.json`), printed on stderr in three lines --
`Error: <failed>: <cause>; observed: <observed>`, `fix: <remedy>`,
`cause: <operation>.<cause>; <page>#<anchor>` -- and the command exits with
the cause's status: 2 for a usage refusal, 69 for a retryable one, else 1.

| command | what it does |
|---|---|
| `envelope build --point P --code C --service S [--impact …] [--detail …] [--remedy …] [--context K=V]… [--fallback] [--out FILE]` | builds one envelope (`Failure`, or `Failure.orFallback` with `--fallback`), prints it as JSON and writes it to `FILE` |
| `envelope read FILE` | reads an envelope back and prints `render()`, then its `chain()` |
| `declaration cause --id … --code … --failed … --cause … --observed … --remedy … --test … [--exit N] [--usage] [--value K=V]…` | holds one cause to the declaration rules: each problem a line, or the refusal it says with the values given, the placeholders they leave unfilled and its exit status |
| `declaration check FILE` | holds every functionality of a product's `errors list --json` listing to the same rules |
| `telemetry status\|set <off\|errors\|usage>\|failure\|show\|flush\|settings --product ID --app APP [--app-version V]` | the product's telemetry, the files its app keeps: its status, the user's answer, a failure reported as the app reports it, the queue as it will go, sending it, and the telemetry section of the app's Settings in a window of its own |
| `support report --product ID --app APP --description … [--subject …] [--email …] [--with-failure]`, `support status` | files a report as Help → Report a Problem files it, and reads support's answer to each report filed |
| `program run NAME [--identifier ID --team TEAM] [--set K=V]… [--withhold PREFIX]… [--stdin] [-- ARGUMENTS]` | runs the installed program through `WisentProgram`: found only in `$HOME/.local/bin` then `$HOME/.stado/bin`, admitted only when its publisher signed it, its output handed on as it comes; SIGTERM or SIGINT stops its whole process group, a second kills it; exits with its status, or 128 + the signal that ended it |

Its telemetry is the product's, under `WISENT_TELEMETRY_HOME`, else
`$XDG_STATE_HOME/<product>/telemetry`, else `~/.local/state/<product>/telemetry`;
`WISENT_TELEMETRY_COLLECTOR_URL`, `WISENT_SUPPORT_URL` and `DO_NOT_TRACK` are
read as an app reads them. `telemetry settings` needs a logged-in macOS
session; outside one it is refused saying so.

## Test

`swift test` builds `wisent-errors-swift` beside the test bundle, and every
Swift case runs it as a process (`tests/swift-cli/CommandCase.swift`), its
environment cleared and given only `HOME`, `TMPDIR` and `XDG_*` inside a
directory of the case's own under the checkout's `.build`, and the product's
own variables the case names (`WISENT_TELEMETRY_HOME`,
`WISENT_TELEMETRY_COLLECTOR_URL`, `WISENT_SUPPORT_URL`, `DO_NOT_TRACK`).
`EnvelopeBuildTests`, `ExplainedTests`, `DescribedTests`,
`DeclarationRuleTests`, `ConsentAndStoreTests`, `UnreachedDeliveryTests` and
`SupportRefusalTests` need nothing beyond the machine.
`AdmissionTests`, `RunOutputTests` and `RunStopTests` run real programs
installed into the case's home: the Node.js-signed node
`WISENT_PROGRAM_TEST_NODE` names and the fleet's stado
`WISENT_PROGRAM_TEST_STADO` names (`.wisent-release.json` installs it through
its `test_products`). `SettingsWindowTests` drives the window through the
Accessibility API, so it needs a logged-in session and the Accessibility
permission for the process running the tests. `ReachedDeliveryTests` runs
against the real collector named by `WISENT_TELEMETRY_TEST_COLLECTOR`, with
`WISENT_TELEMETRY_TEST_APP_ID` an app it declares;
`FailingDeliveryTests` against `WISENT_TELEMETRY_TEST_FAILING_COLLECTOR`, a
collector deployment that answers with a server error (an Echo that cannot
reach its database), whose case checks that the events stay queued under the
collector's own failure. `SupportServiceTests` runs against the support
service of [support.md](../support.md). A case whose variable or capability
is missing fails naming it, never passes.
