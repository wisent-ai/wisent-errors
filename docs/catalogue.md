# The catalogue

`catalogue/codes.json` (version 1) is the single source of truth for the
fleet's failure vocabulary. `codegen/generate.mjs` is what turns it into
code, and the generated modules are the only copies the runtimes carry. The
tables on this page restate the catalogue for reading convenience; if this
page and the catalogue ever disagree, the catalogue is right, and
`node codegen/generate.mjs --check` is the command that notices generated
code drifting from it.

The semantics were extracted verbatim from
`wisent-compute/stado-rs/src/failure.rs`, the one implementation whose
derived status ladder had stayed correct; the HTTP status map and the
exit-code rule each arrived from three identical copies held by other
products. The catalogue's `provenance` field records exactly this.

## The seven codes

Derived fields — severity, retryable, outage, HTTP status — come from the
catalogue, never from a call site.

| code | severity | retryable | outage | http_status | operator summary |
|---|---|---|---|---|---|
| `config` | critical | no | yes | 503 | our deployment configuration is incomplete or wrong |
| `auth` | warning | no | no | 401 | the credentials this command used were rejected |
| `not_found` | warning | no | no | 404 | what the command asked for is not there |
| `rate_limit` | warning | yes | no | 429 | an upstream is throttling us |
| `timeout` | error | yes | yes | 504 | an upstream did not answer in time |
| `infra_down` | critical | yes | yes | 503 | infrastructure we depend on is unreachable |
| `unknown` | error | no | no | 500 | the command failed and we could not attribute the failure |

What each code means, from the catalogue's own `meaning` fields:

- `config` — a value the process needs was absent or malformed. Ours to fix,
  and no amount of retrying changes it.
- `auth` — an upstream refused the identity we presented. Retrying with the
  same credential repeats the refusal.
- `not_found` — the request named something absent. A server error is never
  classified here: collapsing 5xx into "nothing there" is what let a storage
  outage read as an empty queue.
- `rate_limit` — the request was well formed and refused for pace. Worth
  repeating later, unchanged.
- `timeout` — no verdict arrived. The operation may or may not have
  happened, which is why it counts as our outage.
- `infra_down` — a dependency did not answer at all. Nothing about the
  request was wrong.
- `unknown` — the last resort. A failure that stays `unknown` is a gap in
  classification, not a kind of failure, and worth reading as a defect in
  whoever emitted it.

Severities are exactly three: `warning`, `error`, `critical`. There are
exactly seven codes; why an eighth was declined is in
[boundary](boundary.md).

## Classifying an upstream status

`fromUpstreamStatus` / `from_upstream_status` / `Code::from_upstream_status`
/ `Code.fromUpstream(status:)` classify the HTTP status an upstream answered
one of our calls with, identically in all four runtimes. Exact matches are
checked before ranges; ranges are inclusive; anything unmatched is
`unknown`.

| status | code |
|---|---|
| 401, 403, 407 | `auth` |
| 404, 410 | `not_found` |
| 408, 504 | `timeout` |
| 429 | `rate_limit` |
| 501, 505 | `config` |
| 500–599 (any other) | `infra_down` |
| anything else | `unknown` |

501 and 505 sit ahead of the 5xx range on purpose. The catalogue defines
`infra_down` as "a dependency did not answer at all" — and a 501 or a 505
did answer. A server saying it does not implement the method, or does not
speak the version, is our deployment being incomplete: retrying cannot help,
so `config` is the honest code. A 5xx is `infra_down` and never `not_found`.

## The exit-code rule

`RETRY_EXIT` is 69 (`EX_UNAVAILABLE`). Retryable codes exit with it; every
other code keeps the exit code the caller already chose, so a CLI's own
conventions survive adoption. The rule is exposed as `exitCode(code, chosen)`
/ `exit_code(code, chosen)` / `Code::exit_code(chosen)` /
`Code.exitCode(chosen:)`.

## The failure-point grammar

A `failure_point` is a dotted lowercase path, one segment or more:

```
^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*)*$
```

The depth carries no meaning. The catalogue's own examples run from one
segment (`cli`) to four (`cli.host.user.create`), because real products emit
both, and a grammar that refuses what five products already emit is the
package being wrong. What is validated is the shape — lowercase,
dot-separated, no empty segment — because that is all a shared rule can
honestly check. The product is not required as a segment because `service`
is already a field of every envelope. Which points exist is each product's
own business; see [boundary](boundary.md).

The pattern is stated once: `ci/check.mjs` fails if the catalogue and the
schema disagree on it. The envelope the codes travel in is
[envelope](concepts/envelope.md).
