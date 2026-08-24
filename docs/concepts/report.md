# Report

A report is a failure leaving the process that classified it. The package
ships three report surfaces: `render` (one line for a human and machines at
once), `chain` (the cause chain flattened for a reader in a hurry), and — for
Swift desktop components only — `WisentFailureReporter`, a Probierz intake
transport. Everything else about transport is deliberately not owned here:
each product keeps its own emitter ([boundary](../boundary.md)).

## render: one line, both audiences

`render(envelope)` / `failure.render()` returns one line: a human sentence
built entirely from derived fields, then the envelope JSON, on the same line
so grep finds both.

The sentence is `<operator summary> — <whose><retry>`:

- `<operator summary>` — the catalogue's per-code sentence
  (`operatorSummary(code)`).
- `<whose>` — `our failure` when [`outage`](outage.md) is true, otherwise
  `the request or its credentials`.
- `<retry>` — `; retry later` when [`retryable`](retryability.md) is true,
  otherwise `; retrying will not help`.

Captured from a real run:

```
infrastructure we depend on is unreachable — our failure; retry later {"failure_point":"toy.queue.read","error_code":"infra_down","service":"toy","impact":"one queue read","severity":"critical","retryable":true,"outage":true,"detail":"Error: connect ECONNREFUSED 127.0.0.1:19799"}
```

The sentence answers the only question that decides what the reader does
next — ours or theirs — and every word of it comes from the catalogue, so a
call site cannot soften or inflate it. The separator is an em dash (U+2014)
in every runtime, byte-identical, which the conformance harness relies on.

## chain: the cause chain, flattened

`chain(envelope)` / `failure.chain()` returns one row per layer,
outermost first, `<failure_point> [<code>] <detail or ->`:

```
toy.cli.registry-pull [infra_down] -
toy.store.read [infra_down] error sending request for url (http://127.0.0.1:8765/api/object)
```

A `-` marks a layer with no detail. The rows exist because a nested envelope
is precise but slow to read, and the first minutes of an incident are spent
finding what the innermost layer already said.

## WisentFailureReporter: the one transport in the repository

`WisentFailureReporter` (Swift only, `swift/Sources/WisentErrors/Report.swift`)
POSTs envelopes to a Probierz intake. It exists because two native desktop
clients — oko-desktop and wisent-ios — needed a shared way to report, and one
rule carries the whole file: **reporting must never fail the caller**.

- **Configuration is the process environment, read at call time** so a
  launcher that sets it late still wins: `PROBIERZ_INTAKE_URL` (origin only —
  `/v1/failures` is appended) and `PROBIERZ_INTAKE_TOKEN` (the bearer).
- **Loopback fallback.** With either variable absent it tries
  `http://127.0.0.1:9790` with the token read from
  `~/.probierz/intake-token` — the file the intake itself creates on first
  run, and exactly the configuration a Finder-launched app inherits nothing
  of. Reading that 0600 file can fail for a sandboxed app; that failure is
  the same no-op as the file being absent.
- **With neither available, `report` is a no-op.** Misconfiguration ends the
  same way as a refusal or an unreachable intake: the report is dropped and
  the app behaves exactly as before.
- **Off the caller's path.** One ephemeral `URLSession` with five-second
  request and resource timeouts; the POST runs in a detached task; the
  response body is ignored and a non-2xx answer is swallowed.
- **A salvage overload.** `report(failurePoint:code:service:detail:impact:cause:)`
  coerces like `Failure.orFallback` — unknown code string becomes `.unknown`,
  a malformed point is kept verbatim with the violation in `context` — so a
  crash handler can report with whatever strings it has.

What actually leaves the process, captured against a toy intake with
`PROBIERZ_INTAKE_URL=http://127.0.0.1:19790` and
`PROBIERZ_INTAKE_TOKEN=toy-token`:

```
intake: POST /v1/failures
intake: authorization: Bearer toy-token
intake: body: {"failure_point":"toy.dispatch.bounded-rotation","error_code":"rate_limit","service":"toy","impact":"one model request","severity":"warning","retryable":true,"outage":false,"detail":"all bounded 'claude-code' credentials unavailable for agent","cause":{"failure_point":"toy.gateway.oauth-refresh","error_code":"auth","service":"toy","impact":"one credential refresh","severity":"warning","retryable":false,"outage":false,"detail":"invalid_grant -- Refresh token not found or invalid"}}
```

The full session is in [integrate/swift](../integrate/swift.md); the two
environment variables are in [configuration](../configuration.md).

## Invariants

- **A report never raises.** `render` and `chain` are pure functions of the
  envelope; the reporter swallows every transport failure. An error path
  that dies reporting takes the diagnosis with it.
- **Nothing else in this repository ships or logs anything.** The Rust,
  Python, and JavaScript runtimes return strings; the products own their
  pipes.
- **The rendered line is part of the contract.** Its bytes are compared
  across runtimes indirectly — the JSON half is the conformance surface, and
  the sentence is derived from catalogue strings the table probes compare
  per code.

## Not to be confused with

- **The envelope.** The [envelope](envelope.md) is the data; a report is
  the data leaving.
- **Probierz itself.** The reporter targets *a* Probierz intake; what
  Probierz does with a failure report is Probierz's documentation, not this
  package's.
