# Walkthrough: proving a checkout

What "the four runtimes are one behaviour" looks like when you actually
run it. Every output block below is a verbatim capture from this
repository on a machine with `node`, `python3`, `cargo`, and `swift`
installed — the harness needs all four because it builds and runs all four
emitters. What each check defends is in [conformance](conformance.md);
what the failures look like is in the [runbook](runbook.md).

## The gate

```
$ node ci/check.mjs
ok    generated code matches the catalogue
ok    schema and catalogue name the same codes
ok    schema and catalogue name the same severities
ok    the failure point pattern is stated once
ok    every golden envelope obeys the schema
ok    runtimes agree (11 case(s) + 45 vocabulary row(s), 0 failing)

all checks passed
```

Exit 0. Six `ok` lines, four checks: the first runs the generator in
`--check` mode, the middle four compare the catalogue against the schema
and every golden envelope against both, and the last runs the whole
conformance harness and reports its summary line. This is the one command
to run before trusting a checkout, and the one CI runs before anything
ships.

## The harness, on its own

```
$ node tests/conformance.mjs
ok    credential-refused  (js, python, rust, swift)
ok    throttled  (js, python, rust, swift)
ok    store-unreachable  (js, python, rust, swift)
ok    nested-refusal  (js, python, rust, swift)
ok    silent-skip  (js, python, rust, swift)
ok    unattributed  (js, python, rust, swift)
ok    quiet-refusal  (js, python, rust, swift)
ok    single-segment  (js, python, rust, swift)
ok    deep-segment  (js, python, rust, swift)
ok    salvaged-malformed  (js, python, rust, swift)
ok    salvaged-absent  (js, python, rust, swift)
ok    derived vocabulary  (45 rows, js, python, rust, swift)

11 case(s) + 45 vocabulary row(s), 0 failing
```

Exit 0. Each `ok` line is one golden envelope from
`tests/conformance/cases.tsv` that all four runtimes emitted
byte-identically — the eleven are real failures this fleet produced while
the vocabulary lived in six copies. The `derived vocabulary` line is the
45 probe rows of `tests/conformance/table.tsv`: every code's severity,
retryability, outage flag, HTTP status, exit code, and operator summary;
the upstream-status classifications including 200 and 600; the exit-code
remap given a caller's chosen code; both trim rules across the padded,
exact-width, and no-space edge cases; and membership answers for
`toString`, `__proto__`, `constructor`, and friends.

The first run after a fresh clone takes as long as `cargo build` and
`swift build` take — the harness builds the Rust and Swift emitters itself
rather than reporting RUNTIME MISSING on a machine that merely has not
built yet. Warm, the whole gate runs in about two seconds.

## The generator, on its own

```
$ node codegen/generate.mjs --check
unchanged  rust/src/codes.rs
unchanged  python/wisent_errors/codes.py
unchanged  js/codes.mjs
unchanged  swift/Sources/WisentErrors/Codes.swift
```

Exit 0. Four `unchanged` lines mean the committed generated modules are
exactly what the catalogue derives; a `DRIFTED` line and exit 1 mean
someone edited a generated file or the catalogue without regenerating —
what that looks like, and what to do, is in the [runbook](runbook.md).

## Reading a red run

Green is one shape; red has several, each meaning something different —
a drifted generated file, a schema disagreeing with the catalogue, a
runtime emitting different bytes, a toolchain missing from the machine.
The [runbook](runbook.md) captures each one for real, by breaking a
scratch copy of this repository and pasting what the gate said.
