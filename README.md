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
  "remedy": "wait for the provider's rate window to reset, or add a bounded credential for the agent",
  "cause": {
    "failure_point": "brama.gateway.oauth-refresh",
    "error_code": "auth",
    "service": "brama",
    "impact": "one credential refresh",
    "severity": "warning",
    "retryable": false,
    "outage": false,
    "detail": "invalid_grant -- Refresh token not found or invalid",
    "remedy": "sign the subscription's account in again: the provider no longer honours the stored refresh token"
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

`remedy` is what would fix it: the command to run, the declaration to change,
the dependency to bring back. A refusal that names what failed and why but not
what fixes it leaves its reader to rediscover the fix, which is the same work
the refusal was supposed to save. It is `null` only where nothing the reader
does can help, and the key is always present, like `detail`.

## Every functionality declares how it fails

"Operation did not succeed" is a failure nobody analysed. The analysis belongs
to the functionality, done once, for every cause it can meet — including the
ones nobody has met yet, because whoever meets one first has nothing else to
go on. The unit is the functionality, not the command: one command runs
several functionalities (a registry read, a store write, a connection to a
host), and many run with no command at all — a worker's loop, an API route, a
desktop screen, a routine. `wisent_errors::operation` is where it is written
down; an `Operation` is one functionality, named by its failure point:

```rust
use wisent_errors::{Cause, Code, Operation};

pub static FLEET_UNDECLARED: Cause = Cause {
    id: "fleet-undeclared",
    code: Code::Refused,
    usage: false,
    exit: None,
    failed: "placing '{name}' in fleet '{fleet}'",
    cause: "the registry declares no fleet named '{fleet}'",
    observed: "declared fleets: {declared}",
    remedy: "declare it with `stado fleet create {fleet}`, or name a declared fleet with --fleet",
    test: "tests/fleet/enroll_failures.rs::enroll_refuses_an_undeclared_fleet",
};

pub static ENROLL: Operation = Operation {
    id: "stado.fleet.enroll",
    entries: &["stado fleet enroll", "Desktop: Hosts → Enroll a machine"],
    uses: &[&REGISTRY_WRITE, &HOST_CONNECT],
    summary: "register a machine verified over SSH",
    docs: "https://stado.wisent.com/docs/cli/fleet-enrollment",
    causes: &[&FLEET_UNDECLARED /* , every cause of its own steps */],
    warnings: &[],
};
```

`entries` are every way a user or a program starts the functionality, as they
meet it. `uses` are the functionalities it runs: their causes are met here
without being declared again (`Operation::met` lists them all, each with the
functionality that declares it). A functionality only others run names no
entry; one made only of what it uses declares no cause of its own.
```

One declaration gives everything a cause is shown as, so none of them can say
something the others do not:

- the refusal: `Cause::sentence(values)` is `<what failed>: <cause>; observed:
  <state>`, and `Cause::fix(values)` the remedy, `{name}` filled from the
  values the raising code supplies;
- the envelope: `Cause::failure(point, service, values)` with `detail`,
  `remedy` and `context.cause` set;
- the exit status: `Cause::exit_code(product_failure_exit)` is
  `Code::USAGE_EXIT` (2) for a usage refusal, `Code::RETRY_EXIT` (69) for a
  retryable code and the product's own status otherwise;
- the listing a product prints from `<product> errors list|show`
  (`Operation::to_json`: `operation`, `entries`, `uses`, `summary`, `docs`,
  `causes`) and its documentation page (`Operation::markdown`), one anchored
  entry per cause, so every refusal is on the page verbatim.

`Operation::problems` refuses a declaration that is not one: a cause without
its test (`tests/<area>/<file>::<name>`), an empty `failed`, `cause`,
`observed` or `remedy`, a cause declared `unknown` (the catch-all a declaration
replaces), a retryable usage refusal, a duplicate id, an empty entry, a
functionality that uses itself, one with no cause and nothing it uses, a page
that is not https. `catalogue_problems` reads a product's whole catalogue: a
functionality declared twice, one using a functionality the catalogue does not
list, and one nothing starts.

A JavaScript product declares the same thing as plain objects —
`{ id, entries, uses, summary, docs, causes }`, each cause `{ id, code,
usage, exit, failed, cause, observed, remedy, test }` — and `@wisent/errors`
gives it the same rules and the same JSON: `fill`, `sentence`, `fix`,
`causeExit`, `anchor`, `causeProblems`, `operationProblems`,
`catalogueProblems`, `met` and `catalogue(operation, failureExit)`, which
prints exactly what `Operation::to_json` prints. A product keeps no copy of
these rules of its own.

### The lint a product runs

`ci/error-standard.mjs` holds a product's tree to the same standard:

```
$ node ci/error-standard.mjs scan ../stado/stado-rs/src
../stado/stado-rs/src/cli/workload/runners/weles/browser.rs:295: "did not succeed" says the operation failed without the step, the cause or the fix (1 in this file, baseline 0); ...
$ node ci/error-standard.mjs catalogue catalogue.json --repository ../stado --entries entries.json
ok    stado.fleet.enroll: 21 declared cause(s)
```

`scan` refuses an error message holding one of the catalogue's
`generic_sentences` inside a string literal; a baseline lets a product adopt
the rule before every old message is rewritten, and may only shrink.
`catalogue` applies the declaration rules to the JSON a product's `errors list
--json` prints, whatever language declares it, and the whole-catalogue rules
above. With `--repository` it also reads each cause's test: a test file the
repository does not hold, or one that never names the test, is refused. With
`--entries`, a JSON list of every entry the product has (each command, route,
screen and routine, as the product's own inventory reads them), an entry no
functionality names is refused, so a way into the product with no declared
failures is visible. `generic_sentences_in` / `genericSentencesIn` are the one
line rule both runtimes scan with.

## Every functionality that loses its caller something declares a warning

A failure catalogue says how a functionality can go wrong. A warning says what
it does when it goes right and its caller still loses something, so the caller
reads it before confirming: an item purged for good, every consumer's grant
withdrawn, a secret written to a plain-text file, a password changed at its
provider, money spent. It is declared on the same `Operation`, beside the
causes, in `warnings`:

```rust
use wisent_errors::{Hazard, Operation, Warning};

pub static REMOVED_FOR_GOOD: Warning = Warning {
    id: "removed-for-good",
    hazard: Hazard::Irreversible,
    effect: "{id} and every saved version of it are removed",
    consequence: "nothing restores them, not restore and not restore --at",
    safeguard: "keep a copy with `skarbiec backup <directory>`, which `skarbiec backup restore` puts back",
    confirm: "rerun with --yes",
    test: "tests/purge/purge.sh::purge_without_yes_removes_nothing",
};
```

`hazard` is one of six, each a loss the caller cannot take back by running
another command of the same product:

| hazard | the functionality |
|---|---|
| `irreversible` | removes or rewrites something nothing in the product restores afterwards |
| `overwrites` | puts something else in place of the current state; what it replaces is kept only where the warning says |
| `cuts-off-access` | takes access a person or a program has now |
| `exposes-secret` | lets a secret value leave the place that protects it: a plain-text file, a screen, another person or system |
| `external-change` | changes a system outside the product, which the product cannot undo |
| `costs-money` | spends money |

Most functionalities declare none, and that is the rule, not a gap: a warning
on an ordinary read or a recoverable edit teaches its reader to confirm
without reading, which is the one thing a warning exists to prevent. A
functionality warns exactly when it asks for a confirmation, and asks for one
exactly when it warns.

One declaration gives everything a warning is shown as:

- before confirming: `Warning::unconfirmed(values)` is `<effect>;
  <consequence>; nothing was done. Before confirming: <safeguard>. To go
  ahead: <confirm>`, answered only when the functionality did nothing;
  `sentence`, `safeguard` and `confirmation` give the parts to a confirming
  dialog;
- the listing a product prints from `<product> warnings list|show`
  (`Operation::warnings_json(page)`: `operation`, `entries`, `summary`,
  `warnings`, each with its `doc` anchor on the product's warnings page) and
  that page (`Operation::warnings_markdown`, empty for a functionality that
  warns of nothing).

`Operation::problems` refuses a warning that is not one: an empty `effect`,
`consequence`, `safeguard` or `confirm`, a generic sentence in any of them, a
test that is not `tests/<area>/<file>::<name>`, a malformed or duplicate id.
A JavaScript product declares the same objects and `@wisent/errors` gives it
`HAZARDS`, `warningSentence`, `unconfirmed`, `warningAnchor`,
`warningProblems`, `warningsCatalogue(operation, page)` and
`warningsMarkdown`, with the same rules and the same JSON.

`ci/warning-standard.mjs` holds a product to it:

```
$ node ci/warning-standard.mjs warnings.json --repository ../skarbiec --confirmations confirmations.json
ok    skarbiec.item.purge: 3 declared warning(s)
```

It applies the declaration rules to the product's `warnings list --json`; with
`--repository` it reads each warning's test; with `--confirmations`, a JSON
list of every entry that asks for a confirmation before it acts, it refuses an
entry that asks while no functionality it starts declares what for, and a
functionality that warns while none of its entries asks, so the warning is
never read before it runs.

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

An envelope carries its `detail` whole: `failure()`, `Failure::detail` and the
fallback builders strip only the whitespace around it, because a cut detail is a
cut diagnosis. `trimDetail(text, limit)` / `trim_detail` exists for a product
that prints a detail into a narrower place; the width is always the caller's
argument and the package has no width of its own.

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

The Rust crate's `telemetry` feature and the Swift package's `WisentTelemetry`
are how an installed copy reports what failed on a user's machine: with the
user's consent (`off`, `errors`, `usage`), with the home directory and host
name taken out, queued on disk and sent to Echo's app collector without ever
holding the user. Both keep the same files, so a product's command line and
its app share one consent. `WisentFailureReporter` reports through it, for the
product the app's Info.plist declares.
[docs/telemetry.md](docs/telemetry.md) is the contract,
[docs/swift-reporter.md](docs/swift-reporter.md) the Swift side, and
`tests/telemetry/` runs both against the real collector.

The same feature files support reports: `Telemetry::file_report` and
`Telemetry::reports` in Rust, `WisentTelemetry.fileReport` and `reports` in
Swift, and `WisentSupportWindow` for an app's Help → Report a Problem. A
report carries the product, version, system and installation, and with the
user's leave the last failure; the key that reads its replies back stays on
the machine. [docs/support.md](docs/support.md) is the contract, and
`tests/telemetry/` runs both clients against a real `wisent-customer-support`.

Every event the reporter can send is declared once in `telemetry::EVENTS`,
with its consent and every property, and the queue takes only a declared one,
so a product's privacy page can list exactly what goes out. The reporter also
counts the frustration signals only a client sees (`frustration.repeat_failure`,
`frustration.usage_loop`, `frustration.help_after_failure`) without any
threshold of its own ([docs/telemetry.md](docs/telemetry.md)).

The `diagnosis` feature is a product's `doctor`: one `diagnosis::Check` per
functionality of its failure catalogue, tried now or skipped with why, and
`diagnosis::problems` fails the product's test when a functionality has no
check ([docs/diagnosis.md](docs/diagnosis.md)).

`Code::from_upstream_status` / `from_upstream_status` / `fromUpstreamStatus`
classify an HTTP status the same way in all three. A 5xx is `infra_down` and
never `not_found`: collapsing server errors into "nothing there" is what let a
storage outage read as an empty queue. A 402 Payment Required is `auth`: the
vendor refuses the account the credential belongs to until it pays, and
repeating the call repeats the refusal (`node --test
tests/upstream/payment-required.mjs`).

`render` prints one line: the code's summary, then whose the failure is, then
whether retrying helps, then the envelope. Whose it is comes from the
catalogue's `whose` field for that code, the same in every runtime (`Code::whose`
/ `whose` / `whose` / `Code.whose`): `our failure` for `config`, `timeout` and
`infra_down`; `the credentials the request presented` for `auth`; `what the
request named` for `not_found`; `the pace of the requests, not their content`
for `rate_limit`; `a rule we wrote, not the request's credentials` for
`refused`; and `not yet attributed to either side` for `unknown`. It used to be
chosen from `outage` alone, so a policy refusal read as a problem with
credentials.

### CLI output, behind `cli-output`

The Rust crate also carries what every Wisent CLI prints and reads, off by
default so the envelope stays dependency-free. With
`features = ["cli-output"]`, `wisent_errors::cli_output` gives
`read_json(path)` (refusing with `failed to read <path>` or
`invalid JSON in <path>`, the cause attached), `output(&value, text)` (pretty
JSON, or with `text` one `path: value` line per field from the same document)
and `text_lines`, the flattening behind it: keys joined with `.`, array items
as `[index]`, `-` for null and for an empty array or object.

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

Every product that restated this envelope by hand consumes the package
instead. `ci/find-implementations.mjs` answers "who still restates this"
against the tree as it is now.

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

Consumers may sit on different revisions, and that is stated rather than tidied:
a consumer bumps when the diff it would pick up touches something it calls, and
proves that diff before moving. The catalogue, the schema and the derivations
are what every consumer must agree on; a revision that changes none of them is
inert for a consumer that never calls what it added. An unpinned spec lets a
product pick up a rule change and drop it again with no commit anywhere
recording either move. A lockfile stops a checkout from drifting; it does not
stop the command a person types.

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
