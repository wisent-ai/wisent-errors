# Quick start

How do you emit your first envelope? Pin the package at an exact commit,
import your runtime, and build one failure. Every runtime is dependency-free
on purpose — no serde, no validator, no npm tree — so adoption costs one
dependency line and nothing else.

## Pin the commit

Every consumer names the exact revision in its own dependency spec, not just
in a lockfile:

```
npm    "@wisent/errors": "github:wisent-ai/wisent-errors#<sha>"
cargo  wisent-errors = { git = "https://github.com/wisent-ai/wisent-errors", rev = "<sha>" }
pip    wisent-errors @ git+https://github.com/wisent-ai/wisent-errors@<sha>#subdirectory=python
spm    .package(url: "https://github.com/wisent-ai/wisent-errors", revision: "<sha>")
```

The manifests sit where each tool expects them: `package.json` and
`Package.swift` at the repository root, a root Cargo workspace naming
`rust/`, and the Python package under `python/` (hence the `subdirectory`).
A lockfile stops a checkout from drifting; it does not stop the command a
person types, which is why the pin lives in the spec.

## JavaScript

```js
import { failure, raise, render } from '@wisent/errors';

const envelope = failure({
  failurePoint: 'brama.dispatch.bounded-rotation',
  code: 'rate_limit',
  service: 'brama',
  impact: 'one model request',
  detail: providerText,
});
console.error(render(envelope));
```

`failure` returns the envelope as a plain object with `severity`,
`retryable`, and `outage` filled in from the catalogue. `raise` throws the
same envelope wrapped in a `FailureError`; `render` returns one human
sentence followed by the envelope JSON on the same line, so grep finds
both. TypeScript declarations ship in `js/index.d.ts`.

## Python

```python
from wisent_errors import failure, raise_failure, render

envelope = failure(
    failure_point="stado.cli.registry-pull",
    code="infra_down",
    service="stado",
    impact="the registry read this command needed",
    detail=str(error),
)
print(render(envelope))
```

All arguments are keyword-only. `raise_failure` raises a `FailureError`
carrying the envelope.

## Rust

```rust
use wisent_errors::{Code, Failure};

let refused = Failure::new("brama.gateway.oauth-refresh", Code::Auth, "brama")?
    .impact("one credential refresh")
    .detail(provider_text)
    .with_context("subscription", id);
eprintln!("{}", refused.render());
```

`Failure::new` returns `Result<Failure, Invalid>`; the builder methods
`impact`, `detail`, `caused_by`, and `with_context` fill the rest.
`Failure` implements `Display` and `std::error::Error`, and `to_json()`
serializes with the schema's key order.

## Swift

```swift
import WisentErrors

let refused = try Failure(failurePoint: "accounts.create", code: .notFound, service: "growth-tactics")
    .detail(providerText)
print(refused.render())
```

The Swift package also ships `WisentFailureReporter`, a Probierz intake
transport for desktop components; see [runtimes](runtimes.md).

## Inside an error path, never throw

`failure` / `Failure::new` are strict and reject malformed input, which is
right at a call site that wants to fail loud. Inside an error path — where an
exception destroys the diagnosis being carried — use the salvage builders:
`failureOrFallback` (JS), `failure_or_fallback` (Python),
`Failure::or_fallback` (Rust), `Failure.orFallback` (Swift). They never fail:
an absent point becomes `unknown`, a malformed one is kept verbatim, and each
violation is recorded in `context` under a `wisent_errors.` key, so the
defect travels in the data instead of becoming an exception raised inside a
`catch`.

## Prove the copy you pinned

From a clone, one command runs everything that must hold before the package
ships — generated code matches the catalogue, schema and catalogue agree,
every golden envelope obeys the schema, and the four runtimes agree byte for
byte:

```bash
node ci/check.mjs
```

It needs `node`, `python3`, `cargo`, and `swift` on the machine, because the
harness builds and runs all four emitters; see
[conformance](conformance.md). The seven codes and everything derived from
them are in [catalogue](catalogue.md); the adoption path for a whole product
is [integration](integration.md).
