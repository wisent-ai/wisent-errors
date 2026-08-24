# Failure point

`failure_point` is where it broke: a dotted lowercase path, one segment or
more, chosen by the call site. It is the first field of every envelope and
the first thing a reader greps for. The package owns only the *shape* of a
failure point; which points exist is each product's own registry
([boundary](../boundary.md)).

## The grammar

```
^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*)*$
```

Each dot-separated segment starts with a lowercase letter; inside a segment,
lowercase letters, digits, and *single* `-` or `_` separators are allowed; a
segment never ends with a separator and never doubles one (`--`, `__`); no
segment is empty. The pattern is stated once — the catalogue and the schema
both carry it, and `ci/check.mjs` fails if they disagree (`the failure point
pattern is stated once`).

The catalogue's own examples run from one segment (`cli`) to four
(`cli.host.user.create`), because real products emit both.

## Depth carries no meaning

Quoting the catalogue's `failure_point.note`: the rule used to be
`<service>.<surface>.<operation>`, exactly three segments — invented from
examples rather than read out of the registries — and it moved twice in one
hour when the migrations reached real products: probierz and growth-tactics
are two-segment, and stado's ids come from the clap subcommand path and run
from one segment (`cli`) to four (`cli.host.user.create`). A grammar that
refuses what five products already emit is the package being wrong. What is
validated is the shape, because that is all a shared rule can honestly
check: lowercase, dot-separated, no empty segment.

The product is not required as a segment because `service` is already a
field of every envelope.

## Validation per runtime

JS and Python compile the catalogue's pattern
(`FAILURE_POINT_PATTERN`); Rust and Swift implement the same rule by hand
(`valid_failure_point` / `isValidFailurePoint`) to stay dependency-free, and
the conformance cases (`single-segment`, `deep-segment`,
`salvaged-malformed`) hold the implementations together.

The strict builders trim surrounding whitespace and refuse anything that
does not match, with the exact sentences (all captured from real runs):

- JS: `TypeError: failurePoint "Not A Point" is not a dotted lowercase path`
- Python: `TypeError: failure_point 'Not A Point' is not a dotted lowercase path`
- Rust: `Invalid::FailurePoint` displaying `failure_point "Not A Point" is
  not a dotted lowercase path`
- Swift: `Invalid.failurePoint` whose `message` is `failure_point "Not A
  Point" is not a dotted lowercase path`

## The salvage path keeps it verbatim

Inside an error path, the salvage builders never throw. A *malformed* point
is kept verbatim — an operator still needs the bad string — with
`context["wisent_errors.failure_point"] = "malformed"` recorded beside it.
An *absent* point becomes `unknown` with
`context["wisent_errors.failure_point"] = "absent"`. Captured:

```json
{"failure_point":"Not A Point","error_code":"unknown","service":"unknown",
 "impact":null,"severity":"error","retryable":false,"outage":false,"detail":null,
 "context":{"wisent_errors.failure_point":"malformed","wisent_errors.service":"absent"}}
```

The schema validator in `ci/check.mjs` allows a malformed point in exactly
this one circumstance — when `context` records it as `malformed` — and
otherwise reports `<case>.failure_point ... is not a dotted lowercase path,
and context does not record it as malformed`.

## Invariants

- **Lowercase, dotted, never empty.** The shape is the whole contract.
- **Yours to name.** Which points exist, how deep they go, and whether they
  come from a subcommand path or a hand-kept registry is the product's
  business. stado's run `cli` to `cli.host.user.create`; probierz and
  growth-tactics are two-segment.
- **Written only by the package's builders in a consuming tree.** A product
  source line that writes a `failure_point:` key into a literal is what
  `ci/no-handrolled-envelope.mjs` reports ([integration](../integration.md)).

## Not to be confused with

- **`service`.** The failure point says where in the code; `service` says
  which product. That is why the product name is not a required first
  segment.
- **A stack trace.** A failure point is a stable, greppable name for a
  place, not a snapshot of the call stack. It survives refactors that keep
  the place's meaning.
