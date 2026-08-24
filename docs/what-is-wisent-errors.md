# What is wisent-errors

One failure envelope for the whole Wisent fleet: one vocabulary of seven
codes, one shape, one place to look a code up. Four runtimes — Rust, Python,
JavaScript, Swift — are generated from one catalogue and proven byte-identical
to each other. The whole product is three moving parts: a catalogue that
declares, a generator that derives, and a conformance harness that proves the
runtimes are one behaviour.

## The catalogue declares

`catalogue/codes.json` is the single source of truth. It names the seven
codes — `config`, `auth`, `not_found`, `rate_limit`, `timeout`, `infra_down`,
`unknown` — and, for each, everything derivable: `severity`, `retryable`,
`outage`, the HTTP status a service answers with, and an operator summary. It
also states the upstream-status classification, the exit-code rule, and the
`failure_point` grammar. The semantics were extracted verbatim from the
reference implementation (`wisent-compute/stado-rs/src/failure.rs`), so the
first migration could not change what anything does; the catalogue records
that provenance in its own `provenance` field.

A call site chooses where it broke (`failure_point`), what the layer below
said (`detail`), and which subject it concerns (`service`, `impact`,
`context`). It never chooses `severity`, `retryable`, or `outage`: those come
from the catalogue, which is why one code cannot come to mean different
things in different products. The full table is in [catalogue](catalogue.md);
the shape it travels in is in [envelope](envelope.md).

## The generator derives

`codegen/generate.mjs` is the only thing allowed to read the catalogue at
build time. It writes one generated module per language — `rust/src/codes.rs`,
`python/wisent_errors/codes.py`, `js/codes.mjs`,
`swift/Sources/WisentErrors/Codes.swift` — so every runtime carries the same
table. Generated files are committed: a consumer needs no build step, and
`node codegen/generate.mjs --check` fails if any generated file drifts from
the catalogue. The hand-written part of each runtime — building, salvaging,
rendering an envelope — wraps its generated module; see
[runtimes](runtimes.md).

## The harness proves

`tests/conformance.mjs` makes each runtime emit every golden envelope in
`tests/conformance/cases.tsv` plus a dump of the whole derived vocabulary,
and compares all of them against the expected column and against each other.
That comparison is what turns four implementations into one behaviour — and
it is exactly the check whose absence let one product quietly lose the
vocabulary while five kept hand-rolled copies of it. `node ci/check.mjs` runs
that harness plus three structural checks before anything ships; see
[conformance](conformance.md).

## What travels

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

`cause` is the one field this package added to what the fleet already had:
the failure underneath this one, recursively. A gateway refusing a request
because a provider refused a token because a vault refused a read is three
failures, and reporting only the outermost is how a day goes into finding
what the innermost already said.

## What it is not

wisent-errors owns the vocabulary and the shape, not the sentences or the
pipes. Product messages, provider text, logging transport, and each product's
registry of failure points stay in the products. The boundary is stated
precisely in [boundary](boundary.md); how a product adopts the envelope is
[integration](integration.md); the fastest path to a first envelope is
[quick-start](quick-start.md).
