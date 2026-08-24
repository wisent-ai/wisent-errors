# Outage flag

`outage` is a boolean on every envelope: is our side broken, as opposed to
the request being wrong? It is derived from the [code](code.md), never chosen
at a call site. It answers the first question an operator asks of any
failure line — ours or theirs — and it is the first half of the
[rendered](report.md) sentence: `our failure` versus `the request or its
credentials`.

## The mapping

| code | outage | why |
|---|---|---|
| `config` | yes | our deployment is incomplete or wrong |
| `auth` | no | the credential was refused; our side answered |
| `not_found` | no | the request named something absent |
| `rate_limit` | no | the upstream is healthy and throttling us |
| `timeout` | yes | no verdict arrived — the operation may or may not have happened, which is why it counts as our outage |
| `infra_down` | yes | infrastructure we depend on is unreachable |
| `unknown` | no | unattributed; claiming an outage without attribution would page someone for a typo |

In the Rust runtime the mapping is literally
`matches!(self, Self::Config | Self::Timeout | Self::InfraDown)`.

## Independent of retryability, on purpose

The two booleans cut differently, and collapsing them loses real cases:

| | retryable | not retryable |
|---|---|---|
| **outage** | `timeout`, `infra_down` | `config` |
| **not an outage** | `rate_limit` | `auth`, `not_found`, `unknown` |

`config` is the case that keeps the axes honest: it is entirely our fault
and retrying still will not help — someone has to change a value. And
`rate_limit` is the mirror: nothing on our side is broken, yet the same
request is worth sending again later.

This is also why two native clients' `offline` code is *deliberately not an
outage* in their local definition: a device with no signal must not tell its
owner our infrastructure is down ([boundary](../boundary.md)).

## Where it is read

- **The envelope** — filled at build time by every runtime.
- **The rendered line** — `our failure` / `the request or its credentials`
  ([report](report.md)).
- **Downstream paging and dashboards** — the flag exists so that decision is
  made once, in the catalogue, instead of per product. What a product does
  with it (page, count, ignore) stays the product's business.

## Invariants

- **Never an argument.** No builder in any runtime accepts an outage flag.
- **Checked everywhere.** `ci/check.mjs` re-derives it for every golden
  envelope (`<case>.outage is <x>, catalogue says <y>`); the conformance
  table dumps it per code from all four runtimes.
- **A 5xx is never `not_found`.** The catalogue's `not_found` meaning states
  the incident that earned the rule: collapsing 5xx into "nothing there" is
  what let a storage outage read as an empty queue. The upstream-status
  classifier encodes it — any unlisted 5xx is `infra_down`, an outage
  ([http-status-and-exit-code](http-status-and-exit-code.md)).

## Not to be confused with

- **Severity.** `timeout` is an outage at severity `error`; `config` is an
  outage at `critical`. Loudness is its own axis ([severity](severity.md)).
- **An incident.** The flag classifies one failure. Whether many such
  failures constitute a declared incident is operational judgment, outside
  this package ([boundary](../boundary.md)).
