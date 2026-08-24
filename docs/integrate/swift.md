# Integrating the Swift runtime

The SwiftPM package is `wisent-errors`, its `Package.swift` at the repository
root so a dependency resolves; the product is the `WisentErrors` library
(target under `swift/Sources/WisentErrors`). Platforms: macOS 13, iOS 13 —
iOS 13 and not newer because nothing in the library uses a newer API and
wisent-ios, one of the two clients this runtime was written for, deploys to
15.8; "a floor picked from taste rather than from the sources refused the
product it was built for" (`Package.swift`). Zero dependencies.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/wisent-ai/wisent-errors", revision: "<sha>")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "WisentErrors", package: "wisent-errors")
    ])
]
```

A path dependency works the same (`.package(path: "../wisent-errors")`) and
is how the run below was produced.

## A complete consumer, compiled and executed

```swift
import Foundation
import WisentErrors

let refused = try Failure(failurePoint: "toy.gateway.oauth-refresh", code: .auth, service: "toy")
    .impact("one credential refresh")
    .detail("invalid_grant -- Refresh token not found or invalid")

let throttled = try Failure(failurePoint: "toy.dispatch.bounded-rotation", code: .rateLimit, service: "toy")
    .impact("one model request")
    .detail("all bounded 'claude-code' credentials unavailable for agent")
    .causedBy(refused)

print("render: \(throttled.render())")
for row in throttled.chain() { print("  \(row)") }

do { _ = try Failure(failurePoint: "Not A Point", code: .auth, service: "toy") }
catch let error as Invalid { print("strict refusal: \(error.message)") }

let salvaged = Failure.orFallback(failurePoint: nil, code: .unknown, service: nil)
print("salvaged: \(salvaged.toJSON())")

WisentFailureReporter.shared.report(throttled)
// The reporter hands the POST to a detached task and returns at once; a
// process that exits immediately would take the report with it. A real app
// keeps running — this demo waits instead.
Thread.sleep(forTimeInterval: 2)
```

`swift build` (Build complete) then run — output, verbatim:

```
render: an upstream is throttling us — the request or its credentials; retry later {"failure_point":"toy.dispatch.bounded-rotation","error_code":"rate_limit","service":"toy","impact":"one model request","severity":"warning","retryable":true,"outage":false,"detail":"all bounded 'claude-code' credentials unavailable for agent","cause":{"failure_point":"toy.gateway.oauth-refresh","error_code":"auth","service":"toy","impact":"one credential refresh","severity":"warning","retryable":false,"outage":false,"detail":"invalid_grant -- Refresh token not found or invalid"}}
  toy.dispatch.bounded-rotation [rate_limit] all bounded 'claude-code' credentials unavailable for agent
  toy.gateway.oauth-refresh [auth] invalid_grant -- Refresh token not found or invalid
strict refusal: failure_point "Not A Point" is not a dotted lowercase path
salvaged: {"failure_point":"unknown","error_code":"unknown","service":"unknown","impact":null,"severity":"error","retryable":false,"outage":false,"detail":null,"context":{"wisent_errors.failure_point":"absent","wisent_errors.service":"absent"}}
```

With the reporter pointed at a toy intake
(`PROBIERZ_INTAKE_URL=http://127.0.0.1:19790`,
`PROBIERZ_INTAKE_TOKEN=toy-token`), the intake received — captured live:

```
intake: POST /v1/failures
intake: authorization: Bearer toy-token
intake: body: {"failure_point":"toy.dispatch.bounded-rotation","error_code":"rate_limit",...}
```

The scaffolding script that reproduces this run is
[examples/swift-consumer.sh](../examples/swift-consumer.sh).

## Swift-specific behaviour worth knowing

- **The throwing initializer is the strict builder.**
  `try Failure(failurePoint:code:service:)` throws `Invalid.failurePoint`
  (`message`: `failure_point "<point>" is not a dotted lowercase path`) or
  `Invalid.empty("service")` (`message`: `service must not be empty`). An
  off-catalogue code is unrepresentable: `Code` is an enum whose raw values
  are the catalogue strings (`.notFound = "not_found"`).
- **Builder methods return copies** — `impact(_:)`, `detail(_:)`,
  `causedBy(_:)`, `withContext(_:_:)` on a value type; `detail` trims to
  `detailLimit` (2000).
- **`Failure.orFallback(failurePoint:code:service:)` takes optionals** and
  never throws; violations land in `context` under `wisent_errors.` keys.
- **`toJSON()` sorts context keys** so the bytes match the other three
  runtimes; the conformance harness checks this rather than assumes it.
- **`WisentFailureReporter` never fails the caller.** Environment first
  (`PROBIERZ_INTAKE_URL` + `PROBIERZ_INTAKE_TOKEN`), loopback +
  `~/.probierz/intake-token` as fallback, no-op with neither; detached
  five-second POST, answer ignored. Full contract in
  [concepts/report](../concepts/report.md); the variables in
  [configuration](../configuration.md).
- `Code`, `Severity`, and `Failure` are `Sendable`; `Code` and `Severity`
  are `Codable` and `CaseIterable`.

## Guard your tree

```bash
node ci/no-handrolled-envelope.mjs <your-source-tree>
```

The guard scans `.swift` files too. Full API:
[reference/swift](../reference/swift.md); adoption strategy:
[integration](../integration.md).
