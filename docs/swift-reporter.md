# The Swift reporter

`WisentFailureReporter` sends envelopes to a Probierz intake from desktop and
iOS components. One rule carries it: reporting never fails the caller.

```swift
import WisentErrors

let refused = try Failure(failurePoint: "brama.gateway.oauth-refresh", code: .auth, service: "brama")
    .impact("one credential refresh")
    .detail(providerText)

// Never throws, never blocks: the POST runs on a detached task and the caller
// returns before a byte leaves. A report the intake did not take is said on
// stderr, so a quiet intake is never mistaken for a healthy app.
WisentFailureReporter.shared.report(refused)

// A process about to exit awaits the intake's answer instead of guessing how
// long the report needs: `settled` runs once the report is accepted, refused
// or unreachable, and at once when reporting is off.
await withCheckedContinuation { (settled: CheckedContinuation<Void, Never>) in
    WisentFailureReporter.shared.report(refused) { settled.resume() }
}
```

## Where the intake comes from

The environment is read at call time, so a launcher that sets it late still
wins: `PROBIERZ_INTAKE_URL` (no path; `/v1/failures` is appended) and
`PROBIERZ_INTAKE_TOKEN` (the bearer). With either absent, the running intake's
own files are read: the address it listens on from `~/.probierz/intake-url`,
written when it binds, and the token from `~/.probierz/intake-token`, created on
its first run. That is exactly the configuration a Finder-launched app inherits
nothing of.

With no token file, `report` is a no-op. A token whose intake never wrote its
address, or either file that exists but cannot be read, is said on stderr and
reporting stays off.

## What is said on stderr

Every sentence starts with `wisent-errors:`.

| sentence | meaning |
|---|---|
| `failure report to <url> was not sent: <cause>` | the transport failed; the intake was never reached |
| `failure report to <url> was not accepted: HTTP <status>: <body>` | the intake answered something other than `{"accepted": true}` |
| `failure report to <url> was not accepted: HTTP <status> with no body` | the intake answered without a body |
| `failure report to <url> was not accepted: HTTP <status>, body is not JSON (<cause>): <body>` | the intake answered a body that does not parse |
| `... was not accepted: an answer that is not HTTP ...` | the transport answered without an HTTP status in place of `HTTP <status>` |
| `the intake token <path> has no address beside it (...)` | the token file exists but `intake-url` does not; reporting is off |
| `the <file> <path> cannot be read, so failure reports are off: <cause>` | a sandboxed app, or a file the process may not read |
| `the <file> <path> is empty, so failure reports are off` | the token or address file holds nothing |
| `the intake address <url> is not a URL, so failure reports are off` | the environment or `intake-url` names an address that does not parse |

## Try it

`sh docs/examples/swift-consumer.sh` builds a scratch consumer of the checkout
under `.build/swift-consumer`, starts a toy intake on a kernel-assigned loopback
port, hands its address to the consumer through a named pipe and prints what the
intake received. The consumer awaits `settled` before it exits; the intake
answers one request and exits, and is stopped if the consumer fails before it
sends one.
