# Code

A code is the classification of a failure: one of exactly seven lowercase
strings, declared in `catalogue/codes.json` and carried by every envelope as
`error_code`. Everything mechanical about a failure — [severity](severity.md),
[retryability](retryability.md), the [outage flag](outage.md), the
[HTTP status and exit code](http-status-and-exit-code.md) — is derived from
the code, which is why the code is the one field worth being strict about.

## The seven values

| code | meaning (from the catalogue's `meaning` field) |
|---|---|
| `config` | A value the process needs was absent or malformed. Ours to fix, and no amount of retrying changes it. |
| `auth` | An upstream refused the identity we presented. Retrying with the same credential repeats the refusal. |
| `not_found` | The request named something absent. A server error is never classified here: collapsing 5xx into 'nothing there' is what let a storage outage read as an empty queue. |
| `rate_limit` | The request was well formed and refused for pace. Worth repeating later, unchanged. |
| `timeout` | No verdict arrived. The operation may or may not have happened, which is why it counts as our outage. |
| `infra_down` | A dependency did not answer at all. Nothing about the request was wrong. |
| `unknown` | The last resort. A failure that stays unknown is a gap in classification, not a kind of failure, and it is worth reading as a defect in whoever emitted it. |

The full derived table is in [catalogue](../catalogue.md). The semantics were
extracted verbatim from `wisent-compute/stado-rs/src/failure.rs` — the
catalogue's `provenance.extracted_from` field records this — so the first
migration could not change what anything does.

## Shape per runtime

JS and Python carry codes as strings and answer membership questions about
them; Rust and Swift make an off-catalogue code unrepresentable:

- **Rust** — `enum Code { Config, Auth, NotFound, RateLimit, Timeout,
  InfraDown, Unknown }`, with `Code::ALL`, `as_str()`, and `parse(&str) ->
  Option<Code>`.
- **Swift** — `enum Code: String, CaseIterable` with camelCase cases and the
  catalogue string as the raw value (`.notFound = "not_found"`), which is the
  spelling the two native clients already used, so neither had to rename
  anything.
- **JS** — `CODES` (a frozen array), `isCode`, `codeOrNull`,
  `codeOrFallback`; the TypeScript union `Code` in `js/index.d.ts`.
- **Python** — `CODES` (a tuple), `code_or_none`, `code_or_fallback`.

## Lifecycle

1. **Chosen at the call site** — by hand where the caller knows what
   happened, or by `fromUpstreamStatus` / `from_upstream_status` /
   `Code::from_upstream_status` / `Code.fromUpstream(status:)` when
   classifying an HTTP answer ([http-status-and-exit-code](http-status-and-exit-code.md)).
2. **Validated at build time** — the strict builders refuse an off-catalogue
   code. Exact sentences, both captured from real runs:
   - JS: `TypeError: code "panic" is not in the catalogue; one of config,
     auth, not_found, rate_limit, timeout, infra_down, unknown`
   - Python: `TypeError: code 'panic' is not in the catalogue; one of config,
     auth, not_found, rate_limit, timeout, infra_down, unknown`
   - Rust and Swift have no such sentence: `Code` is an enum, so the type
     system refuses an off-catalogue code before a message could exist.
3. **Coerced at wire boundaries** — the salvage path never fails: an unknown
   code becomes `unknown` (`FALLBACK`), and JS/Python record the original in
   `context` as `wisent_errors.error_code: "off-catalogue: <text>"`.

## Invariants

- **Never a free-form string.** The schema's `error_code` is an `enum` of the
  seven; a code nobody can look up is a sentence, not a classification.
- **Membership goes through a real set.** The JS predicates answer through a
  `Set`, never `in` or a bare property read: `"toString" in MEANINGS` is
  true, and `__proto__` reads through the prototype chain, so the `in` form
  accepted `toString`, `constructor`, `hasOwnProperty`, and `valueOf` as
  codes — at precisely the wire boundary these predicates exist to guard. The
  conformance table probes exactly those names against every runtime, plus
  the empty string, `AUTH` (case matters: it coerces to `unknown`), and the
  two honest answers `auth` and `infra_down`.
- **Exactly seven.** Why an eighth (`offline`, invented independently by two
  native clients) was declined is recorded in [boundary](../boundary.md).

## Where a code is read

- `severity`, `retryable`, `outage` — filled into every envelope at build
  time.
- `httpStatus(code)` — what a service edge answers
  ([http-status-and-exit-code](http-status-and-exit-code.md)).
- `exitCode(code, chosen)` — what a CLI exits with (same page).
- `operatorSummary(code)` — the one sentence [`render`](report.md) leads
  with.

## Not to be confused with

- **A failure point.** The [failure point](failure-point.md) says *where* it
  broke; the code says *what kind* of failure it is. `service` says *who*.
- **An upstream's own error code.** Azure has an `error_code`; providers have
  theirs. Their words are data and belong in `detail`, verbatim — the guard
  `ci/no-handrolled-envelope.mjs` even names this as an expected false
  positive ([integration](../integration.md)).
