# wisent-errors

One failure envelope for the whole fleet: one vocabulary, one shape, one place to
look a code up.

## Why this exists

The envelope already existed. It was implemented **six times**, once per product,
in three languages:

| implementation | state before this package |
| --- | --- |
| `wisent-compute/stado-rs/src/failure.rs` | the reference; all seven codes |
| `probierz/agent/failure.mjs` | 412 lines, all seven codes |
| `growth-tactics/api/failure.py` | 679 lines, all seven codes |
| `wisent-backend-images/app/failure.py` | 707 lines, all seven codes |
| `wisent-tools/wisent/failure.py` | 328 lines, all seven codes |
| `wisent-customer-support/src/failure.js` | 438 lines, **none of the seven** |
| `brama` | no envelope at all |

Five copies agreed, one had drifted out of the vocabulary entirely, and the
component every model request passes through had none. That last gap cost a full
day: `all bounded 'codex' credentials unavailable for agent` carries no code, no
`failure_point`, and no indication that it is transient — so the only way to
follow it was to walk the layers by hand and read each one's source.

Nothing here is new behaviour. The catalogue is copied verbatim from the
reference implementation so the first migration cannot change what anything does.

## The one rule

**Everything derivable from the code is derived.** A call site chooses where it
broke, what the layer below said, and which subject it concerns. It never chooses
`severity`, `retryable` or `outage`: those come from the catalogue, which is why
one code cannot come to mean different things in different products.

## The envelope

```json
{
  "failure_point": "brama.dispatch.bounded-rotation",
  "error_code": "rate_limit",
  "service": "brama",
  "impact": "one model request",
  "severity": "warning",
  "retryable": true,
  "outage": false,
  "detail": "all bounded 'claude-code' credentials unavailable for agent",
  "cause": {
    "failure_point": "brama.gateway.oauth-refresh",
    "error_code": "auth",
    "service": "brama",
    "impact": "one credential refresh",
    "severity": "warning",
    "retryable": false,
    "outage": false,
    "detail": "invalid_grant -- Refresh token not found or invalid"
  }
}
```

`cause` is the one field this package adds to what the fleet already had, and it
is the whole point. Three layers independently dropped the reason they were
given: a launcher that skipped a subscription with a bare `continue`, a refresh
that logged a status without the body, a credential write that reported failure
without the error. `cause` makes the nesting explicit, so the sentence that
actually explains the outage — here, Anthropic's `invalid_grant` — travels with
the failure instead of being reconstructed by hand.

`detail` is required. A failure reported without the reason the layer below gave
is the defect this package exists to prevent.

## Use it

```js
import { failure, raise, render } from '@wisent/errors';

raise({
  failurePoint: 'brama.dispatch.bounded-rotation',
  code: 'rate_limit',
  service: 'brama',
  impact: 'one model request',
  detail: providerText,
  cause: refreshFailure,          // optional, recursive
  context: { subscription: id },  // optional, scalars only
});
```

```python
from wisent_errors import failure, raise_failure, render

raise_failure(
    failure_point="stado.cli.registry-pull",
    code="infra_down",
    service="stado",
    impact="the registry read this command needed",
    detail=str(error),
)
```

```rust
use wisent_errors::{Code, Failure};

let refused = Failure::new(
    "brama.gateway.oauth-refresh",
    Code::Auth,
    "brama",
    "one credential refresh",
    provider_text,
)?
.with_context("subscription", id);
```

`Code::from_upstream_status` / `from_upstream_status` / `fromUpstreamStatus`
classify an HTTP status the same way in all three. A 5xx is `infra_down` and
never `not_found`: collapsing server errors into "nothing there" is what let a
storage outage read as an empty queue.

## What is not in here

- **Product messages.** They go in `detail`, verbatim.
- **Provider text.** It passes through and is truncated, never paraphrased or
  re-classified. Their words are data.
- **New codes.** Seven, exactly as the reference had. A case the seven cannot
  describe is worth adding; nothing found so far is one.
- **Logging plumbing.** Each product keeps its own emitter; this decides the
  content, not the transport.

## Layout

```
catalogue/codes.json          the single source of truth
schema/failure.schema.json    the envelope, checkable from any language
codegen/generate.mjs          one generator, three targets
rust/    crate  wisent-errors
python/  package wisent_errors
js/      package @wisent/errors
tests/conformance/cases.tsv   golden envelopes every runtime must reproduce
ci/check.mjs                  what must hold before this ships
ci/no-handrolled-envelope.mjs the guard a consuming repo runs
```

Generated files are committed, so a consumer needs no build step, and
`ci/check.mjs` fails if they drift from the catalogue.

## How it stays one thing

```
$ node ci/check.mjs
ok    generated code matches the catalogue
ok    schema and catalogue name the same codes
ok    schema and catalogue name the same severities
ok    the failure point pattern is stated once
ok    every golden envelope obeys the schema
ok    runtimes agree (6 case(s), 0 failing)
```

The last line is the mechanism. Three implementations emit every golden case and
are compared against the expected envelope **and against each other**. That check
is what turns three runtimes into one behaviour — and it is exactly the check
whose absence let one product lose the vocabulary while five kept it.

Consumers run the second guard against their own tree:

```
$ node ci/no-handrolled-envelope.mjs ../probierz/agent
hand-built failure envelope in 2 place(s):
  .../probierz/agent/failure.mjs:258  failure_point: point.id,
  .../probierz/agent/failure.mjs:259  error_code: classified.code,
```

## Adopting it

Order by what the absence costs, not alphabetically.

1. **`brama`** — has no envelope and carries every model request. Four message
   sites in `subscription_dispatch/dispatch.rs` (413, 434, 599, 724) and
   `ModelErrorContract` in `core/server.rs`. This is where the day went.
2. **`wisent-customer-support`** — the copy that drifted out of the vocabulary.
3. **`stado-rs`, `probierz`, `growth-tactics`, `wisent-tools`,
   `wisent-backend-images`** — delete the local copy, depend on the package, and
   let the conformance cases prove nothing changed. Roughly 2,500 lines go.

`stado-rs` is the reference: the Rust runtime was extracted from it rather than
rewritten, so its exit-code remap and operator sentences survive the move
unchanged.
