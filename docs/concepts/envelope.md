# Envelope

The envelope is the one shape every Wisent component reports failures in.
`schema/failure.schema.json` (draft 2020-12, `$id`
`https://wisent.ai/schema/failure.v1.json`) states it, checkable from any
language. The fields answer, in order, the questions an operator asks: where
did it break, what kind of failure is it, whose fault, is it worth retrying,
and what exactly did the layer below say.

## Shape

Eight keys are required — `failure_point`, `error_code`, `service`, `impact`,
`severity`, `retryable`, `outage`, `detail` — and `additionalProperties` is
`false`: nothing beyond the two optional keys, `cause` and `context`, is
allowed.

| field | type | who fills it | what it is |
|---|---|---|---|
| `failure_point` | string | call site | where it broke: a dotted lowercase path matching the [failure-point grammar](failure-point.md) |
| `error_code` | string | call site | one of the seven [codes](code.md); never a free-form string — a code nobody can look up is a sentence, not a classification |
| `service` | string, `minLength` 1 | call site | the product that emitted this, as the fleet names it |
| `impact` | string \| null | call site | what the caller lost; free text, because the blast radius of a failure is not a taxonomy |
| `severity` | string | derived | `warning`, `error`, or `critical` — from the code, never chosen at the call site ([severity](severity.md)) |
| `retryable` | boolean | derived | worth running the same thing again, unchanged ([retryability](retryability.md)) |
| `outage` | boolean | derived | our side is broken, as opposed to the request being wrong ([outage](outage.md)) |
| `detail` | string \| null | call site | what the layer below actually said, verbatim and truncated, never paraphrased |
| `cause` | envelope | call site | the failure underneath this one, recursively (`$ref` to the schema itself) |
| `context` | object | call site | identifiers a reader needs to find the subject — a host, a subscription id, a job; values are scalars (string, number, boolean, null) so a log shipper can index them |

## Lifecycle

An envelope exists in exactly three states, and only the first is this
package's:

1. **Built** — by a strict builder (`failure`, `Failure::new`,
   `try Failure(...)`) that refuses malformed input, or by a salvage builder
   (`failureOrFallback`, `Failure::or_fallback`, `Failure.orFallback`) that
   never fails and records each violation in `context` under a
   `wisent_errors.` key. The exact refusal sentences are in the per-runtime
   references ([js](../reference/js.md), [python](../reference/python.md),
   [rust](../reference/rust.md), [swift](../reference/swift.md)).
2. **Serialized** — with keys in the schema's order: `failure_point`,
   `error_code`, `service`, `impact`, `severity`, `retryable`, `outage`,
   `detail`, then `cause` and `context` when present. Two runtimes produce
   the same bytes, so the [conformance harness](../conformance.md) compares
   them literally. Rust and Swift hand-serialize (`to_json()` / `toJSON()`)
   to keep the packages dependency-free; JS uses `JSON.stringify` on an
   object built in that key order; Python uses
   `json.dumps(..., separators=(",", ":"), ensure_ascii=False)`.
3. **Read** — by a person via [`render`](report.md), by a log store as one
   JSON line, or by a schema validator against `failure.schema.json`.

## Invariants

- **Null, not missing.** `impact` and `detail` serialize as `null` rather
  than disappearing: a stable key set is what makes these lines queryable in
  a log store. Three fleet products have no impact axis at all, and a call
  site that already knows its code exactly may have no layer below to quote —
  requiring either buys `impact: "unknown"` and `detail: "unknown"`, which is
  a worse lie than an absent value (the schema's own `description` for
  `detail` says exactly this).
- **Empty is refused.** `service`, `impact`, and `detail` carry
  `minLength: 1` in the schema; the builders trim whitespace and turn an
  all-whitespace optional into `null` rather than an empty string.
- **Derived fields cannot disagree with the code.** `severity`, `retryable`,
  and `outage` come from the generated catalogue module, and `ci/check.mjs`
  re-derives them for every golden envelope: `severity` chosen at a call
  site is how the same code came to mean different things in different
  products.
- **`cause` and `context` are structural.** They are omitted entirely when
  there is nothing to put in them — an empty `context` object is never
  emitted.
- **Context keys order deterministically.** Rust keeps `context` in a
  `BTreeMap` and Swift sorts keys before serializing, so the same envelope is
  the same bytes in every runtime.

## The cause chain

`cause` is a whole envelope, recursively. A gateway refusing a request
because a provider refused a token because a vault refused a read is three
failures, and flattening them to the outermost is how the reason gets lost.
Every runtime ships a `chain` helper that flattens the chain outermost-first
into one row per layer, `<failure_point> [<code>] <detail or ->`, for a
reader in a hurry:

```
toy.dispatch.bounded-rotation [rate_limit] all bounded 'claude-code' credentials unavailable for agent
toy.gateway.oauth-refresh [auth] invalid_grant -- Refresh token not found or invalid
```

(Real output; the whole run is in [integrate/js](../integrate/js.md).)

## Detail is quoted, not written

`detail` carries the layer below's words verbatim, bounded by a hard cut.
The trim rule — strip whitespace at the ends, cut hard at the limit — is the
package's (`trimDetail` / `trim_detail`); the width is the product's, passed
as an argument, with 2000 (`DETAIL_LIMIT`) as the package's own bound. A
word-edge variant (`trimDetailAtWordEdge` / `trim_detail_at_word_edge`)
backs up to a word edge within a 24-character slack and is deliberately
opt-in, because it changes emitted bytes. See [runtimes](../runtimes.md).

## One serialization, one wire example

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

This is golden case `nested-refusal` in `tests/conformance/cases.tsv`; all
four runtimes are proven to emit these exact bytes on every change
([conformance](../conformance.md)).

## Not to be confused with

- **The catalogue.** The envelope is the shape; the
  [catalogue](../catalogue.md) is the vocabulary that travels in it.
- **The rendered report.** [`render`](report.md) is one human sentence plus
  this JSON on one line; the envelope itself carries no sentence.
- **A product's own error type.** Products wrap or raise the envelope
  (`FailureError`, `Failure` as `std::error::Error`); the envelope is what
  crosses process and log boundaries.
