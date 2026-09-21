# The migration, and what it found

The record of how thirteen hand-written copies of this envelope became one
package: which product took what, what each one's own diff showed, and the
defects the migration uncovered on the way. It was the tail of the README
until 2026-09-21, which put that file at 485 lines — past the
three-hundred-line limit every file in this workshop lives under.

## Adopted

Thirteen implementations in four languages, all migrated on 2026-08-13, the day
the package was written. The first seven are the ones an early search of mine
found; the last six are the ones it missed.

| product | what it took | what its own diff showed |
| --- | --- | --- |
| `brama` | the whole envelope; it had none | client bytes unchanged; the dispatcher's refusal now carries the provider's `invalid_grant` as its `cause` |
| `wisent-compute/stado-rs` | the vocabulary it was extracted from | **empty diff**, across all 65,536 `u16` statuses |
| `probierz` | vocabulary, envelope, trim, coercion | 16 lines of 930, all the status ladder |
| `growth-tactics` | vocabulary, derived tables, trim, coercion | 6 lines, all the status ladder |
| `wisent-tools` | vocabulary, derived tables, retry exit, trim, coercion | 2 lines, all the status ladder |
| `wisent-backend-images` | vocabulary, four tables, trim, coercion | 12 lines: the ladder, plus a dangling space |
| `wisent-customer-support` | vocabulary, derived tables, trim, coercion | 5 lines: the ladder, plus stripped padding |
| `wisent-app` | vocabulary, derived tables, trim | 33 pairs: the ladder, plus stripped padding — and a live throw closed |
| `echo-web` | vocabulary, derived tables, trim, coercion | 12 of 178: the ladder, plus the trim's strip |
| `wisent-trade` | vocabulary, derived tables, trim, predicate | 50 of 247: the ladder, the strip — and 18 hostile values that used to throw |
| `wisent-landing-blog` | vocabulary, derived tables, trim, predicate | 14 lines: the ladder, the strip — and a live throw inside a React boundary |
| `wisent-gradio` | vocabulary, derived tables, trim, coercion | 39 lines: the ladder, plus one leading space |
| `oko-desktop` | the seven codes' severity, retryable, outage, and the trim | **empty diff**; it had not drifted |

Roughly 800 lines of duplicated derivation deleted, and every behavioural line of
every diff is one of the three differences named in this file: the missing 407
branch, the unbounded `>= 500`, and the trim stripping whitespace at the ends.
`stado-rs` and `oko-desktop` are the two empty diffs, and they are what make the
other eleven readable as corrections rather than changes.

`wisent-ios` is the fourteenth candidate and is not in the table: it consumes
envelopes rather than defining a vocabulary. It appears here only because the
Swift runtime exists for it and for `oko-desktop`.

## The count was wrong twice, in both directions

`echo-production` looked like a fourteenth consumer and is not: it is a second
working copy of `wisent-ai/echo-web`, with `origin` pointing at an unrelated
17-commit repository that shares no ancestor — which is why its branch read as
gone and why its first push tried to send 1,573 unrelated commits. Its module is
the *older* generation, superseded on 2026-08-04 and never merged. Two agents
migrated two generations of one product before either noticed.

`backends/wisent-app` is the same: a stale clone of `wisent-app` with HEAD at an
ancestor. Neither is a second source of truth, and neither was deleted — a
working copy on someone's disk is theirs.

## Five of them had never been committed

`wisent-backend-images/app/failure.py`, `wisent-gradio/wisent/app/failure.py`,
`wisent-landing-blog/src/lib/failure/`, `wisent-trade/lib/failure/` (eight files,
877 lines) and `wisent-app`'s whole failure service were **untracked**. They
entered version control for the first time in their own migrations.

A copy nobody committed is a copy nobody reviewed, and that is most of the
explanation for how five products drifted the same two lines. It also explains how
`echo-production`'s module survived being superseded without anyone noticing.

## The error path itself was throwing

In `wisent-app`, `wisent-trade`, `wisent-landing-blog` and `echo-web`,
`classifyFailure` read a thrown value outside every `try`, so reporting a failure
threw whenever the value would not let itself be read — a getter that raises, a
`Proxy` whose traps raise, a revoked proxy. All four are reachable from React error
boundaries, and `wisent-trade` and `echo-web` also from a route wrapper whose whole
purpose is that nothing escapes a route handler. `wisent-app`'s was the worst: its
`guard` rethrew the *reporter's* error in place of the value its caller threw,
destroying the original error. An error boundary that loses the error it was handed
is worse than one that reports nothing.

Hostile-value counts, before and after: `wisent-app` 20 → 0, `wisent-trade` 18 → 0,
`echo-web` 37 → 0, `wisent-landing-blog` its boundary case → salvaged. All four fixed
in the classifier rather than in each boundary, so every call site is covered.

This is the invariant `probierz` and `wisent-backend-images` argued for in the first
round, on principle, before anyone had found it happening. It was happening in four
of the five web products.

An earlier version of this section said `echo-web` was the one already safe,
because it guards field reads with a `readField` helper. That was mine and it was
wrong: the helper covers the reads inside it, not the ones outside, and `echo-web`'s
own hostile probe found 37 throws. I published the claim from reading one function
instead of running the probe — which is the same mistake as the search result I
published as a fact, in a section about not doing that.

## Two limits on the evidence, stated rather than buried

For the five untracked modules there is no committed baseline, so the
before-dumps are reconstructions of the file as read, not checkouts of a blob.
`wisent-trade` validated its reconstruction by rebuilding it independently and
matching byte for byte; `echo-production` matched its byte size against the
directory listing. It is still a reconstruction, which is a consequence of the
untracked footnote rather than of the measuring.

And every agent in the second round wrote its dumps into a shared `/tmp` while ten
siblings ran the same instruction. `wisent-gradio` found two of its own "identical"
comparisons had read a sibling's file. Every claim in this table was re-derived in
a private directory afterwards, and all of them held — `oko-desktop` added a
negative control to prove its comparison was even sensitive, and `wisent-trade`
chased a 12-byte size mismatch that turned out to be six em-dashes rather than a
collision. An identical dump is a claim about which files you compared.

## A third search found five more, and the lineage of all of them

Asked whether the migration was finished I answered from a list three times. The
first list came from reading, the second from grepping `failure_point`, the third
from grepping `infra_down` — the one code that is not an ordinary English word.
Each found products the one before it missed: `skarbiec`, `most`, `oko-ios`,
`wisent-desktop-auth` and `weles-web-blog`, plus `skarbiec-hub`, which was examined
and had no implementation at all — one code literal in its own 55-value error
vocabulary, which is a wire format and stays.

Eighteen implementations, four languages. `ci/find-implementations.mjs` now answers
the question a list cannot.

Those five also established where the copies came from, which nobody had asked for:

- `wisent-ios`' classifier is the parent. `oko-desktop`'s header admitted copying
  it. `oko-ios` is a copy of the same parent, identified by the single `URLError`
  member that distinguishes the two candidates — `.callIsActive`, present in
  `wisent-ios` and absent from `oko-desktop`.
- `wisent-desktop-auth` is a sibling copy carrying `oko-desktop`'s header sentence
  with the line naming its source removed. Its body is `wisent-ios`' file with
  "device" changed to "Mac" and a subway tunnel changed to a hotel Wi-Fi.
- `most` holds four blocks byte-identical to pre-migration `stado`, including
  `retryable` with the same variant order, while its status ladder had been retyped
  against `axum::StatusCode` — and that retyped ladder is the part that lost the
  407 branch and the 5xx bound.

**Drift entered exactly where a copy had to be adapted to a local type.** The
verbatim blocks stayed correct for months; the adapted ones did not. That is the
mechanism, and it is why "shared by copying" is not a way of sharing.

## The catalogue contradicting itself

`most` read the catalogue's own words back at it. The 500-599 range called 501 and
505 `infra_down`, which this file defines as "a dependency did not answer at all" —
and a 501 answered. A server saying it does not implement the method is our
deployment being incomplete, so it is `config`, and retrying cannot help. Both are
now exact matches ahead of the range, which flips `retryable` from true to false
for them.

Every consumer that could see a 501 was asked whether that is reachable and what
reads `retryable`, rather than being told it was safe: `wisent-desktop-auth` found
it reachable through a host-configured gateway and better as `config` — the user
now gets "isn't set up correctly" with no retry button instead of "isn't
responding" with one — `oko-ios` found it needs an intermediary proxy and gates only
a button, and `most` found nothing in its workspace reads `retryable` at all and
that it had already classified 501 as `config` in two independent places.

## The intent was written down before the package existed

From `oko-desktop/Sources/Oko/Workspace/OkoFailure.swift`, deleted in its
migration:

> Failure taxonomy shared with the Wisent web app, the Python backends, the Rust
> router and the iOS client, so one outage is named identically wherever it
> surfaces. The Swift reference this file follows is
> `wisent-ios/.../Sources/Services/FailureClassifier.swift`; the codes and their
> retry semantics are copied from it deliberately, not reinvented.

Shared by being copied from another client's file. The first sentence is this
package's entire purpose, written by someone who then implemented it with the one
mechanism that guarantees drift.

## What actually caught the defects

Not this package's own checks. The conformance harness proves three runtimes agree
with each other; it cannot tell you they agree with what the fleet was already
emitting. Only a consumer's own before-and-after diff does that, which is why each
migration was asked to produce one rather than to trust a suite.

That is how four defects in already-pushed code were found within an hour: the
word-edge trim moving operator-visible bytes, a byte offset compared against a
character limit, `-1` used as a position, and a missing `Hash` derive that would
have broken any product keying a map by code. Three of the rules in this package's
first day — three-segment failure points, a mandatory `detail`, a word-edge cut —
were mine from taste rather than read out of the registries, and the migrations
overturned all three.

The strongest single piece of evidence was produced by accident. `probierz` wrote
an equivalence harness to prove the package matched its local module, and that
harness forced a code onto an already-classified object without recomputing: the
package re-derived `severity`, `retryable` and `outage` correctly while the local
side carried stale values. A test written to show the package was unnecessary
demonstrated the exact defect it exists to prevent.
