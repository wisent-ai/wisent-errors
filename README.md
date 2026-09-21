<!-- wisent-banner:start -->
<p align="center">
  <img src="assets/readme-banner.webp" alt="wisent-errors by Wisent" width="100%">
</p>
<!-- wisent-banner:end -->

<!-- wisent-readme-signals:start -->
[![Source](https://img.shields.io/badge/GitHub-Source-181717?logo=github)](https://github.com/wisent-ai/wisent-errors) [![Issues](https://img.shields.io/badge/GitHub-Issues-181717?logo=github)](https://github.com/wisent-ai/wisent-errors/issues) [![Wisent](https://img.shields.io/badge/Wisent-Website-0B0B0B)](https://wisent.com) [![Discord](https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white)](https://discord.gg/qRjpkthq54) [![LinkedIn](https://img.shields.io/badge/LinkedIn-Follow-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/company/wisent-ai/) [![X](https://img.shields.io/badge/X-Follow-000000?logo=x&logoColor=white)](https://x.com/wisentai) [![Enterprise](https://img.shields.io/badge/Enterprise-Book%20a%20call-0B0B0B?logo=calendly)](https://calendly.com/lbartoszcze)
<!-- wisent-readme-signals:end -->

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

## Layout, and how it stays one thing

What each directory holds, and the check that compares three runtimes against
the golden envelopes and against each other, are in
[docs/layout-and-checks.md](docs/layout-and-checks.md). Generated files are
committed, so a consumer needs no build step, and `ci/check.mjs` fails if they
drift from the catalogue.

Consumers run the second guard against their own tree:

```
$ node ci/no-handrolled-envelope.mjs ../probierz/agent
hand-built failure envelope in 2 place(s):
  .../probierz/agent/failure.mjs:258  failure_point: point.id,
  .../probierz/agent/failure.mjs:259  error_code: classified.code,
```

## Adopted

Thirteen implementations in four languages were migrated on 2026-08-13, the day
the package was written, and five more were found by the search that followed.
Which product took what, what each one's own diff showed, the four defects the
migration uncovered and where every copy came from are in
[docs/migration.md](docs/migration.md).

`ci/find-implementations.mjs` answers "who still restates this" against the tree
as it is now; the record beside it says what was already answered.

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

## The eighth code, decided

`oko-desktop` and `wisent-ios` each invented `offline`: retryable, `warning`, and
deliberately not an outage, because a device with no signal must not tell its owner
our infrastructure is down. Two independent inventions clear this package's own bar
for adding something, and adding it would be additive — no consumer emits it, so no
behaviour would move, and both clients could delete about six lines each.

It is still not in the catalogue, for one reason. `http_status` and `exit_code` are
derived for every code, and neither applies to a code no server can observe and no
command can exit with. Putting invented values there is the exact shape of the four
rules this package had to withdraw on its first day. Both clients keep `offline`
beside the seven with the reason written next to it, which costs six lines twice and
invents nothing.

That changes if a third product needs it, or if the catalogue grows a way to say
"this derivation does not apply".
