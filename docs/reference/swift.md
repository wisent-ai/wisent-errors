# Swift API reference

SwiftPM package `wisent-errors` (manifest at the repository root), library
product `WisentErrors`, target under `swift/Sources/WisentErrors`.
Platforms macOS 13 / iOS 13, zero dependencies. All refusal sentences below
are the exact `message` strings.

## Types

### `enum Code: String, CaseIterable, Sendable, Hashable, Codable`

Cases `config`, `auth`, `notFound` (`"not_found"`), `rateLimit`
(`"rate_limit"`), `timeout`, `infraDown` (`"infra_down"`), `unknown` — raw
values are the wire strings, so an off-catalogue code is unrepresentable
and `Code(rawValue:)` is the honest wire-boundary primitive (`nil` for
anything unknown).

| item | contract |
|---|---|
| `Code.retryExit: Int32` | `69` (`EX_UNAVAILABLE`) |
| `severity: Severity` | derived, from the generated table |
| `retryable: Bool`, `outage: Bool` | derived |
| `httpStatus: Int` | the edge status |
| `operatorSummary: String` | the catalogue's per-code sentence |
| `exitCode(chosen: Int32) → Int32` | `retryExit` when retryable, else `chosen` |
| `Code.fromUpstream(status: Int) → Code` | exact matches, then the inclusive 500–599 range → `.infraDown`, else `.unknown` |
| `Code.orFallback(_ text: String?) → Code` | the code, or `.unknown` for `nil` and anything off-catalogue; never fails |

### `enum Severity: String, CaseIterable, Sendable, Hashable, Codable`

Cases `warning`, `error`, `critical`.

### `struct Failure: Sendable, Equatable`

`failurePoint: String`, `code: Code`, `service: String` are `let`;
`impact: String?`, `detail: String?`, `cause: [Failure]`, `context:
[String: String]` are `private(set)` and filled through the builder
methods. `cause` is an array holding at most one element — a value type
cannot hold itself directly, and an array is the indirection; `causedBy`
replaces, never appends. Derived: `severity`, `retryable`, `outage`.

### `enum Invalid: Error, Equatable, Sendable`

| case | `message` |
|---|---|
| `.failurePoint(point)` | `failure_point "Not A Point" is not a dotted lowercase path` |
| `.empty("service")` | `service must not be empty` |

## Building

### `init(failurePoint: String, code: Code, service: String) throws`

The strict builder. Trims `failurePoint` and `service`; throws
`Invalid.failurePoint` when the point fails the grammar
(`isValidFailurePoint` — lowercase dotted path, refusing a trailing
`-`/`_` and doubled separators) and `Invalid.empty("service")` when the
service is blank.

### `Failure.orFallback(failurePoint: String?, code: Code, service: String?) → Failure`

The salvage builder; never throws, takes optionals. An absent/empty point
becomes `unknown` with `wisent_errors.failure_point: absent` in `context`;
a malformed one is kept verbatim with `wisent_errors.failure_point:
malformed`; an absent/empty service becomes `unknown` with
`wisent_errors.service: absent`. The code cannot be off-catalogue — it is
a `Code`; coerce untrusted text with `Code.orFallback` first (which is
what the reporter's salvage overload does).

### Builder methods (return copies — `Failure` is a value type)

| method | contract |
|---|---|
| `impact(_ impact: String)` | trimmed; empty becomes `nil` |
| `detail(_ detail: String?)` | trimmed to `detailLimit` (2000); empty/`nil` becomes `nil` |
| `causedBy(_ cause: Failure)` | sets the failure underneath this one |
| `withContext(_ key: String, _ value: String)` | inserts one context pair |

## Rendering

### `toJSON() → String`

The envelope in the schema's key order, absent optionals written as
`null`. Context keys are sorted before serializing so the bytes match the
other three runtimes. Escaping is the same minimal JSON set (`"`, `\`,
`\n`, `\r`, `\t`, `\u00XX` for other controls).

### `render() → String`

One line: `<operatorSummary> — <whose><retry> <toJSON()>`; em dash
(U+2014), same derived wording as every runtime.

### `chain() → [String]`

One row per cause-chain layer, outermost first:
`<failurePoint> [<code.rawValue>] <detail ?? "-">`.

## Trims

### `trimDetail(_ text: String?, limit: Int = detailLimit) → String`

`nil` becomes empty, both ends trimmed, hard cut at `limit` (characters).

### `trimDetailAtWordEdge(_ text: String?, limit: Int = detailLimit, slack: Int = 24) → String`

The same, cut back to the last space when one falls within `slack`
characters of the bound; right-trimmed. Opt-in, because it changes emitted
bytes.

### Grammar helpers

`isValidFailurePoint(_ point: String) → Bool`, `failurePointPattern`
(the regex as a string), `fallbackCode` (`.unknown`), `detailLimit`
(`2000`).

## `WisentFailureReporter`

The one transport in the repository (`Report.swift`), for desktop
components. One rule carries the whole file: reporting must never fail the
caller.

| member | contract |
|---|---|
| `WisentFailureReporter.shared` | the process's reporter; `init()` is also public |
| `report(_ failure: Failure)` | POSTs `failure.toJSON()` to `<intake>/v1/failures` with `Content-Type: application/json` and `Authorization: Bearer <token>`; never throws, never blocks — the POST runs in a detached task on one ephemeral `URLSession` with five-second request and resource timeouts, the response body is ignored, a non-2xx answer is swallowed |
| `report(failurePoint:code:service:detail:impact:cause:)` | the salvage overload for crash handlers: `code` is a `String` coerced through `Code(rawValue:) ?? .unknown`, point/service coerce like `Failure.orFallback` |

Configuration is the process environment, read at call time — the two
variables and the loopback fallback are in
[configuration](../configuration.md). With nothing configured, `report` is
a no-op: misconfiguration ends the same way as a refusal or an unreachable
intake.

## Executed

Every sentence above is exercised by
[examples/swift-consumer.sh](../examples/swift-consumer.sh) (a scaffolded
consumer plus a toy intake capturing the POST); its captured output is in
[integrate/swift](../integrate/swift.md).
