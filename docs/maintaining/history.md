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

## Why there is no trim

The package once had `trimDetail` / `trim_detail` (a hard cut to a caller's
width) and `trimDetailAtWordEdge` / `trim_detail_at_word_edge`, because four
products cut details by hand. Every width those products passed (60 to 500
characters) was a number no source stated, and a detail cut at one lost the part
past it, which was often the part that said why. When the last consumer quoted
its details whole, the trims were removed from all four runtimes; a detail is
carried and printed whole, its surrounding whitespace stripped.

The trim also taught a rule worth keeping: its first version made the word-edge
cut the default without reading what the fleet did, and the migrations caught it.
Migrating consumers early catches a rule written from taste.

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

