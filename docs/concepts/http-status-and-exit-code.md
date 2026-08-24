# HTTP status and exit code

Two derivations turn a [code](code.md) into numbers the outside world reads:
the HTTP status a service answers with at its edge, and the exit code a
command leaves the process with. Both live in the catalogue (`http_status`
per code; the `exit_code` block), both are generated into every runtime, and
both arrived here from three identical hand-kept copies each — the
catalogue's `provenance` field names the exact files.

There is also a third, inbound mapping: classifying the status an *upstream*
answered one of our calls with. All three are on this page because they are
the three places a number and a code meet.

## Edge HTTP status: code → status

`httpStatus(code)` / `http_status(code)` / `code.http_status()` /
`code.httpStatus` — what a service answers when this failure reaches its
edge.

| code | status |
|---|---|
| `config` | 503 |
| `auth` | 401 |
| `not_found` | 404 |
| `rate_limit` | 429 |
| `timeout` | 504 |
| `infra_down` | 503 |
| `unknown` | 500 |

Captured from the adopted toy service in
[walkthrough-adoption](../walkthrough-adoption.md): an `infra_down` envelope
answers `HTTP/1.1 503 Service Unavailable`, a `rate_limit` one answers
`HTTP/1.1 429 Too Many Requests`.

## Exit code: code → process exit

`RETRY_EXIT` is 69 — `EX_UNAVAILABLE` from `sysexits.h`, on every platform
this fleet runs on. The rule, quoted from the catalogue: "retryable codes
exit with `retry`; every other code keeps the exit code the caller already
chose". Exposed as `exitCode(code, chosen)` / `exit_code(code, chosen)` /
`code.exit_code(chosen)` / `code.exitCode(chosen:)`.

Only the retryable path is remapped so a CLI's own exit-code conventions
survive adoption — a caller that already chose 2 for "bad usage" keeps 2.
Captured from the executed examples:

```
exit_code('infra_down', 3): 69 (RETRY_EXIT = 69)
exit_code('not_found', 3): 3
```

and the compiled Rust consumer in [integrate/rust](../integrate/rust.md)
really exits 69 when its failure is retryable (`echo $?` → `69`).

## Upstream status: status → code

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
so `config` is the honest code. The catalogue's `upstream_status.note`
records that most-server read 501 as config in two independent places before
this fix. A 5xx is `infra_down` and never `not_found`.

Two lines every hand-rolled copy of this ladder got wrong — the missing 407
branch and the unbounded `>= 500` — are exactly why the classifier is owned
here ([integration](../integration.md)).

## Invariants

- **200 and 600 are probed too.** The conformance table classifies statuses
  including 200 and 600 — neither is a failure status, both classify as
  `unknown`, and a runtime that classifies them differently from the others
  is still a disagreement (`tests/conformance/table.tsv`).
- **The remap rule is visible in the probes.** The table carries
  `chosen_exit	2`, so every runtime's dump shows retryable codes answering
  69 and everything else answering 2.
- **Derived for every code.** `http_status` and `exit_code` exist for all
  seven codes — which is the stated reason the catalogue has no `offline`
  code: neither derivation applies to a code no server can observe and no
  command can exit with ([boundary](../boundary.md)).

## Not to be confused with

- **The status our edge answers vs the status an upstream answered us.**
  `httpStatus` is outbound (ours); `fromUpstreamStatus` is inbound (theirs).
  They are not inverses: `fromUpstreamStatus(503)` is `infra_down`, and
  `httpStatus("infra_down")` is 503, but `fromUpstreamStatus(500)` is also
  `infra_down` while `httpStatus("unknown")` is 500.
- **A product's other exit codes.** The package owns one exit code, 69.
  Everything else is the caller's convention, passed through untouched.
