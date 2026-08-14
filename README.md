# wisent-errors

One failure envelope for the whole fleet: one vocabulary, one shape, one place to
look a code up. Four runtimes -- Rust, Python, JavaScript, Swift -- generated from
one catalogue and proven byte-identical to each other.

## Why this exists

The envelope already existed. It was implemented **six times**, once per product,
in three languages — and the interesting part is not the duplication, it is which
half of it drifted.

| implementation | vocabulary | the derived status ladder |
| --- | --- | --- |
| `wisent-compute/stado-rs/src/failure.rs` | seven codes, the reference | correct: 407 present, 5xx bounded |
| `probierz/agent/failure.mjs` | seven codes, agreeing | **no 407 branch, unbounded `>= 500`** |
| `growth-tactics/api/failure.py` | seven codes, agreeing | **no 407 branch, unbounded `>= 500`** |
| `wisent-backend-images/app/failure.py` | seven codes, agreeing | **no 407 branch, unbounded `>= 500`** |
| `wisent-tools/wisent/failure.py` | seven codes, agreeing | **no 407 branch, unbounded `>= 500`** |
| `wisent-customer-support/src/failure.js` | seven codes, agreeing | **no 407 branch, unbounded `>= 500`** |
| `brama` | no envelope at all | — |

Five of five copies had drifted, in the same two lines, away from the one
reference that had them right. A proxy authentication refusal had no code
anywhere but in `stado`, and every copy called a status of 600 a dependency
outage. Nobody noticed, because the vocabulary was the part people compared and
the derived table was the part nobody compared across products.

An earlier version of this file said `wisent-customer-support` held "none of the
seven" codes. That was wrong. It held all seven, spelled identically, with a
matching severity map, retryable set, outage set and status map. The claim came
from a search of mine that found nothing, and I published the absence as a fact
— a negative search result is a claim, not a fact, and the migration that read
the file disproved it in its first ten minutes.

The gap that actually cost a day is the last row. `all bounded 'codex'
credentials unavailable for agent` carries no code, no `failure_point`, and no
indication that it is transient, so the only way to follow it was to walk the
layers by hand and read each one's source.

Nothing here is new behaviour. The catalogue is copied verbatim from the
reference implementation so the first migration cannot change what anything does.

**Everything derivable from the code is derived.** A call site chooses where it
broke, what the layer below said, and which subject it concerns. It never chooses
`severity`, `retryable` or `outage`: those come from the catalogue, which is why
one code cannot come to mean different things in different products.

## The envelope

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

`cause` is the one field this package adds to what the fleet already had, and it
is the whole point. Three layers independently dropped the reason they were
given: a launcher that skipped a subscription with a bare `continue`, a refresh
that logged a status without the body, a credential write that reported failure
without the error. `cause` makes the nesting explicit, so the sentence that
actually explains the outage — here, Anthropic's `invalid_grant` — travels with
the failure instead of being reconstructed by hand.

`detail` and `impact` are optional, and serialize as `null` rather than
disappearing: a stable key set is what makes these lines queryable in a log
store, and `probierz` already indexes `detail` that way. Both were mandatory
until the migrations reached real call sites. Three products have no impact axis
at all — `stado`'s failure points come from its subcommand path and it has never
had one — and two legitimately report a failure with nothing further to say,
because they already know their code exactly and there was no layer below to
quote. Requiring either buys `impact: "unknown"` and `detail: "unknown"`, which
is a worse lie than an absent value. When there **is** a reason from below,
dropping it is the defect this package exists to prevent.

`failure_point` is a dotted lowercase path of one segment or more. This demanded
exactly three until the migrations read the registries: `probierz` and
`growth-tactics` are two-segment, and `stado` runs from `cli` to
`cli.host.user.create`. The depth carries no meaning and the rule stopped
pretending it does.

## Reporting a failure must never fail

An error path that throws takes the diagnosis with it, which is how hours of an
outage end up with no record of why. Two products hold that invariant explicitly,
so the package does too:

```js
import { failureOrFallback } from '@wisent/errors';

// Never throws. An unknown code becomes `unknown`, a malformed failure point is
// kept verbatim because an operator still needs it, and each violation is
// recorded in `context` under a `wisent_errors.` key -- so the defect travels in
// the data instead of becoming an exception raised inside a `catch`.
const envelope = failureOrFallback({ failurePoint: whatever, code: maybe, service });
```

`failure()` and `Failure::new` stay strict, for call sites that want to fail loud.
`codeOrFallback` / `code_or_fallback` / `Code::or_fallback` coerce one code
without throwing; three products wrote that coercion by hand during their
migration, which is the duplication this package exists to remove.

`trimDetail(text, limit)` / `trim_detail` exposes the trim rule with the width as
an argument, because the width is a product's own decision — `stado` and
`probierz` keep 300, `wisent-customer-support` 400, `wisent-tools` 500 — while the
rule for how to cut is the thing that was written six times.

It is a **hard cut**, because that is what all four of those products emit.
`trimDetailAtWordEdge` / `trim_detail_at_word_edge` backs up to a word edge and is
opt-in, and that split exists because the first version had it the other way
round. I made the nicer rule the default without checking what the fleet did, and
five migrations reported the same consequence: it moved the bytes of an
operator-visible log line for every detail longer than the bound that contains a
space, which is nearly all of them. `probierz` measured 60 changed lines out of
930 from that alone.

That is the third time in this package's first day that I wrote a rule from my
own taste instead of reading the registries — after three-segment failure points
and a mandatory `detail`. The migrations were what caught all three, which is an
argument for migrating consumers early rather than for designing more carefully in
private.

Two defects in the word-edge helper came out of the same reviews and are fixed:
the edge was found with `rfind`, comparing a **byte** offset against a character
limit, so 100 CJK characters followed by a space returned 100 characters where the
bound was 300 — two thirds of the allowed detail discarded on any non-ASCII
provider text. And `-1` from "no space at all" was treated as a position, so for
any limit under 24 the last character was silently dropped. Neither was reachable
at the fleet's widths; both were wrong rather than harmless, and the trim rule is
now compared across all three runtimes on eleven probes including both cases.

## Use it

```js
import { failure, raise, render } from '@wisent/errors';

raise({
  failurePoint: 'brama.dispatch.bounded-rotation',
  code: 'rate_limit',
  service: 'brama',
  impact: 'one model request',
  detail: providerText,
  cause: refreshFailure,          // optional, recursive
  context: { subscription: id },  // optional, scalars only
});
```

```python
from wisent_errors import failure, raise_failure, render

raise_failure(
    failure_point="stado.cli.registry-pull",
    code="infra_down",
    service="stado",
    impact="the registry read this command needed",
    detail=str(error),
)
```

```rust
use wisent_errors::{Code, Failure};

let refused = Failure::new("brama.gateway.oauth-refresh", Code::Auth, "brama")?
    .impact("one credential refresh")
    .detail(provider_text)
    .with_context("subscription", id);
```

`Code::from_upstream_status` / `from_upstream_status` / `fromUpstreamStatus`
classify an HTTP status the same way in all three. A 5xx is `infra_down` and
never `not_found`: collapsing server errors into "nothing there" is what let a
storage outage read as an empty queue.

## What is not in here

- **Product messages.** They go in `detail`, verbatim.
- **Provider text.** It passes through and is truncated, never paraphrased or
  re-classified. Their words are data.
- **New codes.** Seven, exactly as the reference had. A case the seven cannot
  describe is worth adding; nothing found so far is one.
- **Logging plumbing.** Each product keeps its own emitter; this decides the
  content, not the transport.

## Layout

```
catalogue/codes.json          the single source of truth
schema/failure.schema.json    the envelope, checkable from any language
codegen/generate.mjs          one generator, three targets
rust/    crate   wisent-errors
python/  package wisent_errors
js/      package @wisent/errors  (+ .d.ts, four consumers are TypeScript)
swift/   library WisentErrors    (two native clients: oko-desktop, wisent-ios)
tests/conformance/cases.tsv   golden envelopes every runtime must reproduce
ci/check.mjs                  what must hold before this ships
ci/no-handrolled-envelope.mjs the guard a consuming repo runs
```

Generated files are committed, so a consumer needs no build step, and
`ci/check.mjs` fails if they drift from the catalogue.

## How it stays one thing

```
$ node ci/check.mjs
ok    generated code matches the catalogue
ok    schema and catalogue name the same codes
ok    schema and catalogue name the same severities
ok    the failure point pattern is stated once
ok    every golden envelope obeys the schema
ok    runtimes agree (6 case(s), 0 failing)
```

The last line is the mechanism. Three implementations emit every golden case and
are compared against the expected envelope **and against each other**. That check
is what turns three runtimes into one behaviour — and it is exactly the check
whose absence let one product lose the vocabulary while five kept it.

Consumers run the second guard against their own tree:

```
$ node ci/no-handrolled-envelope.mjs ../probierz/agent
hand-built failure envelope in 2 place(s):
  .../probierz/agent/failure.mjs:258  failure_point: point.id,
  .../probierz/agent/failure.mjs:259  error_code: classified.code,
```

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

### The count was wrong twice, in both directions

`echo-production` looked like a fourteenth consumer and is not: it is a second
working copy of `wisent-ai/echo-web`, with `origin` pointing at an unrelated
17-commit repository that shares no ancestor — which is why its branch read as
gone and why its first push tried to send 1,573 unrelated commits. Its module is
the *older* generation, superseded on 2026-08-04 and never merged. Two agents
migrated two generations of one product before either noticed.

`backends/wisent-app` is the same: a stale clone of `wisent-app` with HEAD at an
ancestor. Neither is a second source of truth, and neither was deleted — a
working copy on someone's disk is theirs.

### Five of them had never been committed

`wisent-backend-images/app/failure.py`, `wisent-gradio/wisent/app/failure.py`,
`wisent-landing-blog/src/lib/failure/`, `wisent-trade/lib/failure/` (eight files,
877 lines) and `wisent-app`'s whole failure service were **untracked**. They
entered version control for the first time in their own migrations.

A copy nobody committed is a copy nobody reviewed, and that is most of the
explanation for how five products drifted the same two lines. It also explains how
`echo-production`'s module survived being superseded without anyone noticing.

### The error path itself was throwing

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

### Two limits on the evidence, stated rather than buried

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

### The intent was written down before the package existed

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


## Pin the commit

Every consumer names the exact revision in its own dependency spec, not just in a
lockfile:

```
npm    "@wisent/errors": "github:wisent-ai/wisent-errors#<sha>"
cargo  wisent-errors = { git = "https://github.com/wisent-ai/wisent-errors", rev = "<sha>" }
pip    wisent-errors @ git+https://github.com/wisent-ai/wisent-errors@<sha>#subdirectory=python
spm    .package(url: "https://github.com/wisent-ai/wisent-errors", revision: "<sha>")
```

Upgrading therefore costs thirteen deliberate one-line bumps, which is the price
of the guarantee.

The fleet is on three revisions, not one, and that is stated rather than tidied:
seven consumers on `e3014d2`, `oko-desktop` on `75df476`, and six on `2c8a355`.
The spread is provably inert. `e3014d2..2c8a355` is 29 added lines in
`js/` and `python/` only — `codeOrNull` and `isCode` — and touches
`catalogue/`, `schema/` and `rust/` not at all, so every consumer derives from the
identical catalogue whatever it pins. `75df476` differs from `e3014d2` only in the
Swift package's platform floor. Each agent that bumped proved that diff itself
before moving, and the ones that did not bump were right not to churn a repository
for two functions they never call. An unpinned spec was the original instruction, and within one hour
it let one product pick up a rule change and drop it again with no commit anywhere
recording either move. A lockfile stops a checkout from drifting; it does not stop
the command a person types.

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
