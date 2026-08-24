# Conformance

Four runtimes are one behaviour only because a harness proves it, byte for
byte, on every change. This page is the proof machinery: the golden cases,
the vocabulary probes, the harness that compares runtimes against each
other, and the gate that runs before the package ships.

## The gate

```bash
node ci/check.mjs
```

Four checks, each earned by a specific way the fleet's error handling
failed:

1. **generated code matches the catalogue** — it runs
   `codegen/generate.mjs --check`; six hand-kept copies drifted, and one
   lost the vocabulary entirely.
2. **schema and catalogue name the same codes and severities, and state the
   failure-point pattern once** — a schema that disagrees with the table it
   validates is a second source of truth.
3. **every golden envelope obeys the schema, derived fields included** —
   `severity` chosen at a call site is how the same code came to mean
   different things in different products. The schema check is deliberately
   hand-rolled over the fields this schema actually uses rather than pulling
   in a validator: a package every product must adopt has to be cheap to
   adopt, and that includes its own CI.
4. **the runtimes agree** — it runs `tests/conformance.mjs` and reports its
   summary line.

It prints `all checks passed` and exits 0, or names the failing checks and
exits 1.

## The harness

```bash
node tests/conformance.mjs
```

Each runtime emits every golden case; the harness compares all of them
against the expected column **and against each other**. The emitters are
`tests/emit.mjs` (JavaScript), `tests/emit.py` (Python, run via
`/usr/bin/env python3`), `rust/src/bin/emit.rs` (reads the case file on
stdin), and `swift/Sources/emit` (same). The harness builds the Rust and
Swift emitters itself — `cargo build --bin emit` and `swift build` — rather
than requiring the reader to have done it: a harness that reports RUNTIME
MISSING on a fresh clone teaches people to read past that line. The summary
is `<N> case(s) + <M> vocabulary row(s), <F> failing`, exit 0 only when
nothing fails.

## Golden cases

`tests/conformance/cases.tsv` holds one case per line as tab-separated
`key=value` pairs, so all the languages can read it without a JSON parser
and the Rust crate stays dependency-free. An optional field is simply
absent, not an empty column. The cases are real: every one is a failure this
fleet produced while the vocabulary lived in six copies — a revoked OAuth
token, a throttled rotation, an unreachable store, a nested refusal carrying
`invalid_grant` as its `cause`, a one-segment and a four-segment failure
point, an envelope with no `impact` and no `detail`, and two salvage cases
(`builder=or_fallback`) proving the never-fail path emits identical bytes
too.

## Vocabulary probes

Envelope cases prove the shape; `tests/conformance/table.tsv` proves the
vocabulary itself. Each emitter, asked with `--table` (the Rust and Swift
emitters additionally read the probe file on stdin), dumps every code's
severity, retryability, outage flag, HTTP status, exit code, and operator
summary, plus:

- **statuses** — how each interesting upstream status classifies, including
  200 and 600: neither is a failure status, and a runtime that classifies
  them differently from the others is still a disagreement.
- **chosen_exit** — the exit code a caller brings, so the remap rule is
  visible: a retryable code must replace it, everything else must keep it.
- **trim / word rows** — a width and a text per row, comparing both trim
  rules across runtimes, including the padded, exact-width, and no-space
  edge cases that earlier versions got wrong.
- **member rows** — membership asked of untrusted text: `toString`,
  `__proto__`, `constructor`, `hasOwnProperty`, `valueOf`, `prototype`, the
  empty string, `AUTH`, and the two honest answers `auth` and `infra_down`.

The probes live in a data file all the emitters read, because three
emitters carrying their own copy of the question is the same defect as
three products carrying their own copy of the answer.

## What this proves, and what it cannot

The harness proves the runtimes agree with each other and with the golden
column. It cannot prove they agree with what a product was already emitting
— only that product's own before-and-after diff does, which is why each
migration produced one. The vocabulary the harness defends is
[catalogue](catalogue.md); the guards a consuming repository runs against
its own tree are in [integration](integration.md). A healthy run of gate
and harness, pasted in full, is
[walkthrough-conformance](walkthrough-conformance.md); every failure
shape, captured from a deliberately broken scratch copy, is in the
[runbook](runbook.md).
