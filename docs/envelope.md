# The envelope

`schema/failure.schema.json` (draft 2020-12, `$id`
`https://wisent.ai/schema/failure.v1.json`) is the one shape every Wisent
component reports failures in, checkable from any language. The fields
answer, in order, the questions an operator asks: where did it break, what
kind of failure is it, whose fault, is it worth retrying, and what exactly
did the layer below say.

## Fields

Eight keys are required — `failure_point`, `error_code`, `service`,
`impact`, `severity`, `retryable`, `outage`, `detail` — and no extra
properties are allowed beyond the two optional ones, `cause` and `context`.

| field | type | who fills it | what it is |
|---|---|---|---|
| `failure_point` | string | call site | where it broke: a dotted lowercase path matching the [catalogue grammar](catalogue.md) |
| `error_code` | string | call site | one of the seven codes; never a free-form string — a code nobody can look up is a sentence, not a classification |
| `service` | string | call site | the product that emitted this, as the fleet names it |
| `impact` | string \| null | call site | what the caller lost; free text, because the blast radius of a failure is not a taxonomy |
| `severity` | string | derived | `warning`, `error`, or `critical` — from the code, never chosen at the call site |
| `retryable` | boolean | derived | worth running the same thing again, unchanged |
| `outage` | boolean | derived | our side is broken, as opposed to the request being wrong |
| `detail` | string \| null | call site | what the layer below actually said, verbatim and truncated, never paraphrased |
| `cause` | envelope | call site | the failure underneath this one, recursively |
| `context` | object | call site | identifiers a reader needs to find the subject — a host, a subscription id, a job; values are scalars so a log shipper can index them |

## Null, not missing

`impact` and `detail` are optional and serialize as `null` rather than
disappearing: a stable key set is what makes these lines queryable in a log
store. Three fleet products have no impact axis at all, and a call site that
already knows its code exactly may have no layer below to quote — requiring
either buys `impact: "unknown"` and `detail: "unknown"`, which is a worse
lie than an absent value. `cause` and `context` are structural and are
omitted entirely when there is nothing to put in them.

## The cause chain

`cause` is a whole envelope, recursively (`$ref` to the schema itself). A
gateway refusing a request because a provider refused a token because a
vault refused a read is three failures, and flattening them to the outermost
is how the reason gets lost. Every runtime ships a `chain` helper that
flattens the chain outermost-first into one row per layer,
`<failure_point> [<code>] <detail or ->`, for a reader in a hurry.

## Detail is quoted, not written

`detail` carries the layer below's words verbatim, bounded by a hard cut.
The trim rule — strip whitespace at the ends, cut hard at the limit — is the
package's (`trimDetail` / `trim_detail`); the width is the product's, passed
as an argument, with 2000 (`DETAIL_LIMIT`) as the package's own bound. A
word-edge variant (`trimDetailAtWordEdge` / `trim_detail_at_word_edge`)
backs up to a word edge within a 24-character slack and is deliberately
opt-in, because it changes emitted bytes. See [runtimes](runtimes.md).

## One serialization

Envelopes serialize with keys in the schema's order — `failure_point`,
`error_code`, `service`, `impact`, `severity`, `retryable`, `outage`,
`detail`, then `cause` and `context` when present — so two runtimes produce
the same bytes and the [conformance harness](conformance.md) can compare
them literally. `render` prefixes the JSON with one human sentence built
from the derived fields: the operator summary, then "our failure" or "the
request or its credentials" from `outage`, then "retry later" or "retrying
will not help" from `retryable`, all on one line so grep finds both.
