# Integrating a product

How does a product adopt the envelope? Pin the package at an exact commit,
delete the local vocabulary and derived tables, route what the product
already decides through arguments, and run the guard that keeps the envelope
from being hand-built again. Thirteen implementations in four languages took
this path; the whole behavioural diff across all of them was three known
corrections, which is what adopting a shared table is supposed to look like.

## 1. Pin the exact commit

Name the revision in the dependency spec itself — the four spellings are in
[quick-start](quick-start.md). An unpinned spec once let a product pick up a
rule change and drop it again with no commit anywhere recording either move;
a lockfile stops a checkout from drifting, not the command a person types.
Upgrading therefore costs one deliberate one-line bump per consumer, which
is the price of the guarantee.

## 2. Replace the vocabulary, keep your decisions

Delete the local copy of the seven codes, the severity/retryable/outage
tables, the HTTP status ladder, the upstream-status classifier, and the
trim rule — those are the package's. Keep everything that was genuinely
yours, and pass it as an argument:

- **Your failure points.** The package validates only the shape (a dotted
  lowercase path); which points exist stays your registry's business.
- **Your trim width.** `trimDetail(text, limit)` takes the width as an
  argument because it is a product decision — stado and probierz keep 300,
  wisent-customer-support 400, wisent-tools 500. The rule for how to cut is
  the shared part.
- **Your exit codes.** `exitCode(code, chosen)` remaps only the retryable
  path to 69 (`EX_UNAVAILABLE`); every other code keeps the exit code you
  already chose, so your CLI's conventions survive.
- **Your emitter.** The package decides the content of a failure line, not
  the transport; see [boundary](boundary.md).

## 3. Route the reason, don't drop it

Where a layer below gave you a reason, quote it: put its text in `detail`
verbatim (the package truncates, never paraphrases) and attach its envelope
as `cause`. Three layers independently dropping the reason they were given
is the defect this package exists to prevent. When classifying an upstream
HTTP answer, use `fromUpstreamStatus` instead of a local ladder — the two
lines every hand-rolled ladder got wrong (no 407 branch, unbounded
`>= 500`) are exactly the lines it owns.

## 4. Never throw while reporting

Error paths use the salvage builders — `failureOrFallback`,
`failure_or_fallback`, `Failure::or_fallback`, `Failure.orFallback` — which
always produce an envelope and record violations in `context` under
`wisent_errors.` keys. Four web products had reporters that threw on hostile
values (a getter that raises, a revoked `Proxy`) inside React error
boundaries; fixing the classifier rather than each boundary is what covered
every call site.

## 5. Run the guard

```bash
node ci/no-handrolled-envelope.mjs <path> [<path>...]
```

Point it at your own source tree. It reports every line that writes a
`failure_point` or `error_code` key outside this package — quoted or bare,
key or assignment — because a product that writes those keys into a literal
has forked the contract without saying so. It reports sites, not verdicts:
a field declaration, an operator-visible log line whose format is already
parsed, and another API's own `error_code` are legitimate answers, and the
guard says to read the line before believing the count. Exit 0 means a
clean tree; exit 1 means sites to read; exit 2 means no path was given.

The census tool answers the wider question:

```bash
node ci/find-implementations.mjs [<root>...] [--unadopted-only]
```

Two passes, because they answer two different questions. The literal scan
finds files that restate the vocabulary — a file counts when it quotes
`infra_down`, the one code that is not an English phrase, and at least four
of the seven codes in total as string literals. The manifest sweep reads dependency
files (`package.json`, `Cargo.toml`, `Package.swift`, `pyproject.toml`,
`setup.py`, `requirements.txt`) to answer who depends on the package and at
which pinned sha — a fully migrated consumer quotes no codes at all, so it
is invisible to the first pass and only the second can count it.

## What a good migration diff looks like

Small, and explainable line by line. The reference extraction
(`stado-rs`) produced an empty diff across all 65,536 `u16` statuses;
every non-empty diff in the fleet's migration decomposed into the three
known corrections — the missing 407 branch, the unbounded `>= 500`, and the
trim stripping whitespace at the ends. A behavioural change your diff cannot
attribute to one of the package's stated rules is a question to raise, not
to merge. The rules themselves are in [catalogue](catalogue.md) and
[envelope](concepts/envelope.md); the proof they hold everywhere is
[conformance](conformance.md).
