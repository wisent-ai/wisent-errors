# Retryability

`retryable` is a boolean on every envelope: is it worth running the same
thing again, unchanged? It is derived from the [code](code.md), never chosen
at a call site, and it is the one derived field that changes behaviour
rather than presentation — it decides the process [exit
code](http-status-and-exit-code.md) and the second half of the
[rendered](report.md) sentence.

## The mapping

| code | retryable | why |
|---|---|---|
| `config` | no | ours to fix; no amount of retrying changes it |
| `auth` | no | retrying with the same credential repeats the refusal |
| `not_found` | no | the request named something absent; asking again names it again |
| `rate_limit` | yes | the request was well formed and refused for pace; worth repeating later, unchanged |
| `timeout` | yes | no verdict arrived; the same request may get one |
| `infra_down` | yes | nothing about the request was wrong |
| `unknown` | no | retrying an unattributed failure is guessing |

Exactly the three codes where the request itself was fine and the world may
change — `rate_limit`, `timeout`, `infra_down` — are retryable. In the Rust
runtime this is literally the implementation:
`matches!(self, Self::RateLimit | Self::Timeout | Self::InfraDown)`.

## Where it is read

- **The envelope.** Every builder fills `retryable` from the catalogue.
- **The exit code.** `exitCode(code, chosen)` remaps retryable codes to 69
  (`RETRY_EXIT`, `EX_UNAVAILABLE`) and leaves every other exit code alone,
  so a supervisor can restart precisely the failures where restarting can
  help ([http-status-and-exit-code](http-status-and-exit-code.md)).
- **The rendered line.** `render` ends its sentence with `; retry later` or
  `; retrying will not help` — the operator's decision, made for them by the
  catalogue ([report](report.md)).

## Invariants

- **Never an argument.** No builder accepts a retryable flag. "Retryable" is
  a property of the failure kind, not of the call site's mood.
- **Checked everywhere.** `ci/check.mjs` re-derives it for every golden
  envelope (`<case>.retryable is <x>, catalogue says <y>`), and the
  conformance table dumps it per code from every runtime, so one runtime's
  copy cannot quietly diverge.
- **Retryable means unchanged.** The definition is "worth running the same
  thing again, unchanged". A failure that needs a different credential, a
  different name, or a fixed config before the retry is not retryable, which
  is why `auth` and `not_found` are `false` even though a human will
  eventually retry after fixing the cause.

## Not to be confused with

- **The outage flag.** `rate_limit` is retryable and *not* an outage — the
  upstream is healthy and throttling us. `config` is an outage and *not*
  retryable. The two axes are deliberately independent
  ([outage](outage.md)).
- **A retry policy.** How often, how long, with what backoff — that is each
  product's business. The package answers only whether; see
  [boundary](../boundary.md).
