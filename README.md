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

`detail` and `impact` are optional and serialize as `null`; `failure_point` is
a dotted lowercase path of one segment or more, and a malformed one is refused
naming the segment and the character that broke it. Why each rule is what it
is: [docs/history.md](docs/history.md).

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

One declaration gives everything a cause is shown as, so none of them can say
something the others do not:

- the refusal: `Cause::sentence(values)` is `<what failed>: <cause>; observed:
  <state>`, `Cause::fix(values)` the remedy and `Cause::refusal(values)` both
  as one line, `{name}` filled from the values the raising code supplies;
- the envelope: `Cause::failure(point, service, values)` with `detail`,
  `remedy` and `context.cause` set, and any placeholder the raising code
  gave no value for named in `context["wisent_errors.unfilled"]`;
- the exit status: `Cause::exit_code(product_failure_exit)` is
  `Code::USAGE_EXIT` (2) for a usage refusal, `Code::RETRY_EXIT` (69) for a
  retryable code and the product's own status otherwise;
- the listing a product prints from `<product> errors list|show`
  (`Operation::to_json`: `operation`, `entries`, `uses`, `summary`, `docs`,
  `causes`) and its documentation page (`Operation::markdown`), one anchored
  entry per cause, so every refusal is on the page verbatim.

`Operation::problems` refuses a declaration that is not one, in the sentences
[catalogue/declaration.json](catalogue/declaration.json) states once for every
runtime: a cause without its test (`tests/<area>/<file>::<name>`), an empty or
generic `failed`, `cause`, `observed` or `remedy`, a cause declared `unknown`,
a retryable usage refusal, a duplicate id, an empty entry, a functionality
that uses itself, one with no cause and nothing it uses, a page that is not
https, and three that make a refusal say less than it should:

- **a placeholder the renderer never fills.** A placeholder is `{name}`: a
  lowercase letter, then lowercase letters, digits and `_`. `{value:?}`,
  `{error:#}`, `{Path}`, `{deal.title}`, a `{` nothing closes and a `}`
  nothing opened are kept as written, so a reader would see them; each is
  refused, naming the cause, the field, the placeholder and the name to write;
- **raw text where the declaration's own words belong.** `{error}`, `{problem}`,
  `{message}`, `{body}`, `{stderr}` and the other names the layer below's
  answer is passed under belong in `observed`; in `failed`, `cause` or
  `remedy` they are refused;
- **a cause that is only what it wraps.** A `cause` with no word outside its
  placeholders (`{error}`, `{code}: {reason}`) says nothing of why.

`catalogue_problems` reads a product's whole catalogue: a functionality
declared twice, one using a functionality the catalogue does not list, and one
nothing starts.

JavaScript (`@wisent/errors`), Python (`wisent_errors`) and Swift
(`WisentErrors`) declare the same `Operation`s and `Cause`s and hold them to the
same rules with the same sentences: `fill`, `placeholders`, `unfilled`,
`templateProblems` / `template_problems`, `causeProblems` / `Cause.problems`,
`operationProblems` / `Operation.problems`, `catalogueProblems` /
`catalogue_problems`, and the catalogue JSON `Operation::to_json` prints. The
four read a template the same way and are tested against the same probes. A
product keeps no copy of these rules of its own.

### The lint a product runs

`ci/error-standard.mjs` holds a product's tree to the same standard: `scan`
refuses a generic error sentence in its source, `catalogue` applies the
declaration rules to its `errors list --json` and, with `--repository`, reads
its tests and raising sites; what each refuses is in
[docs/layout-and-checks.md](docs/layout-and-checks.md#the-lint-a-product-runs).
Warnings are declared beside causes: [docs/warnings.md](docs/warnings.md).

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
report what failed on a user's machine, with the user's consent and with the
home directory and host name taken out, file a user's support report, and
count the frustration signals only a client sees; every event they can send is
declared once in `telemetry::EVENTS`. The contracts are
[docs/telemetry.md](docs/telemetry.md), [docs/support.md](docs/support.md) and
[docs/swift-reporter.md](docs/swift-reporter.md); `tests/telemetry/` runs both
clients against the real collector and a real `wisent-customer-support`.

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

`render` prints one line: the code's summary, whose the failure is (the
catalogue's `whose` for that code, the same in every runtime), whether retrying
helps, then the envelope. What `whose` says per code, and what the package
leaves to each product: [docs/history.md](docs/history.md).

### CLI output, behind `cli-output`

The Rust crate also carries what every Wisent CLI prints and reads, off by
default so the envelope stays dependency-free. With
`features = ["cli-output"]`, `wisent_errors::cli_output` gives
`read_json(path)` (each refusal a declared cause of
`wisent_errors.cli_output.read_json`: the file absent, a directory, not
readable, not JSON with the line and column, cut short, or JSON of the wrong
shape with the type it was read as), `output(&value, text)` (pretty JSON, or
with `text` one `path: value` line per field from the same document; a result
JSON cannot hold and a closed standard output are declared causes too, never a
panic) and `text_lines`, the flattening behind it: keys joined with `.`, array
items as `[index]`, `-` for null and for an empty array or object.

## Layout, and how it stays one thing

What each directory holds, and the checks that keep the catalogue, the
declaration rules and the four runtimes one thing, are in
[docs/layout-and-checks.md](docs/layout-and-checks.md). Generated files are
committed, so a consumer needs no build step, and `ci/check.mjs` fails if they
drift from the catalogue or this package's own failures break its own rules.

Consumers run the second guard against their own tree:

```
$ node ci/no-handrolled-envelope.mjs ../probierz/agent
Error: reading 41 source file(s) under ../probierz/agent for hand-built envelopes: 2 line(s) write failure_point or error_code outside the package, ...
  ../probierz/agent/failure.mjs:258  failure_point: point.id,
  ../probierz/agent/failure.mjs:259  error_code: classified.code,
```

## More

Who still restates the envelope: [docs/finding-implementations.md](docs/finding-implementations.md).
Why it is shaped so: [docs/history.md](docs/history.md); pinning a revision:
[docs/pinning.md](docs/pinning.md); what changed: [docs/changelog.md](docs/changelog.md).
