# Why the package is the way it is

How the envelope came to be one package, and the rules it had to withdraw on
the way. The README states the current promise; this page keeps the reasons.

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

## Why the fields are what they are

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

## Why the trim is a hard cut

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

## Whose a failure is

`render` says whose a failure is from the catalogue's `whose` for its code:
`our failure` for `config`, `timeout` and `infra_down`; `the credentials the
request presented` for `auth`; `what the request named` for `not_found`; `the
pace of the requests, not their content` for `rate_limit`; `a rule we wrote,
not the request's credentials` for `refused`; and `not yet attributed to either
side` for `unknown`. It used to be chosen from `outage` alone, so a policy
refusal read as a problem with credentials.

## What is not in here

- **Product messages.** A product declares its own causes with
  `operation::Cause`, in its own code, beside the operation that raises them;
  a sentence from the layer below goes in `detail`, verbatim.
- **Provider text.** It passes through and is truncated, never paraphrased or
  re-classified. Their words are data.
- **New codes.** Seven, exactly as the reference had. A case the seven cannot
  describe is worth adding; nothing found so far is one.
- **Logging plumbing.** Each product keeps its own emitter; this decides the
  content, not the transport.

