# The four runtimes

One catalogue, four languages. Each runtime is a generated codes module —
written by `codegen/generate.mjs`, committed, never edited by hand — plus a
hand-written envelope module around it. All four carry zero dependencies on
purpose: a package every product must adopt has to be cheap to adopt, and a
serde or validator requirement is a reason to keep a local copy.

```
rust/    crate   wisent-errors    (root Cargo workspace member)
python/  package wisent_errors   (pip subdirectory=python)
js/      package @wisent/errors  (root package.json; .d.ts included)
swift/   library WisentErrors    (Package.swift at the root; macOS 13, iOS 13)
```

## One API, four spellings

| what | JavaScript | Python | Rust | Swift |
|---|---|---|---|---|
| build, strict | `failure({...})` | `failure(**kw)` | `Failure::new(point, code, service)?` | `try Failure(failurePoint:code:service:)` |
| build, never fails | `failureOrFallback` | `failure_or_fallback` | `Failure::or_fallback` | `Failure.orFallback` |
| throw/raise | `raise` → `FailureError` | `raise_failure` → `FailureError` | `Failure` is `std::error::Error` | `Failure` via the throwing init |
| one line + JSON | `render(envelope)` | `render(envelope)` | `failure.render()` | `failure.render()` |
| flatten causes | `chain(envelope)` | `chain(envelope)` | `failure.chain()` | `failure.chain()` |
| hard trim | `trimDetail(text, limit)` | `trim_detail(text, limit)` | `trim_detail(text, limit)` | `trimDetail(_:limit:)` |
| word-edge trim | `trimDetailAtWordEdge` | `trim_detail_at_word_edge` | `trim_detail_at_word_edge` | `trimDetailAtWordEdge` |
| coerce a code | `codeOrFallback` | `code_or_fallback` | `Code::or_fallback` | `Code.orFallback` |
| membership | `isCode`, `codeOrNull` | `code_or_none` | `Code::parse` → `Option` | `Code(rawValue:)` |
| classify a status | `fromUpstreamStatus` | `from_upstream_status` | `Code::from_upstream_status` | `Code.fromUpstream(status:)` |
| edge HTTP status | `httpStatus(code)` | `http_status(code)` | `code.http_status()` | `code.httpStatus` |
| exit code | `exitCode(code, chosen)` | `exit_code(code, chosen)` | `code.exit_code(chosen)` | `code.exitCode(chosen:)` |
| retry exit | `RETRY_EXIT` (69) | `RETRY_EXIT` (69) | `Code::RETRY_EXIT` (69) | `Code.retryExit` (69) |
| package bound | `DETAIL_LIMIT` (2000) | `DETAIL_LIMIT` (2000) | `DETAIL_LIMIT` (2000) | `detailLimit` (2000) |

JS and Python build envelopes as plain objects/dicts. Rust and Swift build a
`Failure` value whose `code` is a typed enum (`Code::RateLimit`,
`.rateLimit`), so an off-catalogue code is unrepresentable there; the
salvage builders in JS and Python additionally coerce an unknown code to
`unknown` and record it in `context` as `wisent_errors.error_code`.

## The trim rule

`trimDetail` strips whitespace at both ends and cuts hard at the limit. The
limit is an argument because the width is a product's own decision — stado
and probierz keep 300, wisent-customer-support 400, wisent-tools 500 — while
the rule for how to cut is the thing that was written six times.
`trimDetailAtWordEdge` backs up to the last word edge within `slack`
(default 24) characters of the bound and is opt-in, because it changes
emitted bytes. The edge is measured in characters, not bytes: an earlier
Rust version compared a byte offset from `rfind` against a character limit
and discarded two thirds of a non-ASCII detail. Both rules are compared
across runtimes by the [conformance harness](conformance.md).

## Membership goes through a real set

The JS predicates answer membership through a `Set`, never `in` or a bare
property read: `"toString" in MEANINGS` is true, and `__proto__` reads
through the prototype chain, so the `in` form accepted `toString`,
`constructor`, `hasOwnProperty`, and `valueOf` as codes — at precisely the
wire boundary these predicates exist to guard. The harness probes exactly
those names against every runtime.

## Rust specifics

The crate carries no serde: `Failure::to_json()` hand-serializes with the
schema's key order and minimal escaping, so a git dependency costs nothing
downstream. `context` is a `BTreeMap<String, String>`, so context keys
serialize in sorted order. Strict construction returns
`Result<Failure, Invalid>`, where `Invalid` names why the envelope was
refused — an envelope with an unparseable failure point is worse than none,
because it looks like a report.

## Swift specifics

The library exists because two native clients — oko-desktop and wisent-ios —
held their own copies of the envelope. Beyond `Failure` and `Code`, it ships
`WisentFailureReporter`, a Probierz intake transport for desktop components,
built around one rule: reporting must never fail the caller. Configuration
is the process environment, read at call time — `PROBIERZ_INTAKE_URL` (no
path; `/v1/failures` is appended) and `PROBIERZ_INTAKE_TOKEN` (the bearer).
With either absent it tries the loopback default, `http://127.0.0.1:9790`
with the token from `~/.probierz/intake-token`, which is what a
Finder-launched app can still reach; with neither available, `report` is a
no-op. The POST runs off the caller's path — a detached task, a five-second
timeout, the response body ignored, a non-2xx answer swallowed.

## Generated files are committed

Every codes module starts with the same header: generated from
`catalogue/codes.json` by `codegen/generate.mjs`, do not edit. Changing the
vocabulary means changing the catalogue and running the generator;
`node codegen/generate.mjs --check` (and `ci/check.mjs`, which runs it) fails
on any drift between the two. What the vocabulary contains is
[catalogue](catalogue.md); what the envelope looks like is
[envelope](concepts/envelope.md).
