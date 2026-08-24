# Tools reference

Five node scripts, no dependencies. Two run in this repository
(`generate`, `check`); one is the harness they both lean on
(`conformance`); two run against *other* trees (`no-handrolled-envelope`,
`find-implementations`). Every output line below is captured from a real
run.

## `codegen/generate.mjs`

```
node codegen/generate.mjs [--check]
```

The only thing allowed to read the catalogue at build time. Writes the four
generated modules — `rust/src/codes.rs`, `python/wisent_errors/codes.py`,
`js/codes.mjs`, `swift/Sources/WisentErrors/Codes.swift` — and prints one
line per target, `written` or `unchanged`:

```
unchanged  rust/src/codes.rs
unchanged  python/wisent_errors/codes.py
unchanged  js/codes.mjs
unchanged  swift/Sources/WisentErrors/Codes.swift
```

`--check` writes nothing: a target whose bytes differ prints `DRIFTED`
instead, followed by

```
generated code does not match the catalogue; run codegen/generate.mjs
```

and exit 1. Generated files are committed, so a consumer needs no build
step and drift is a diff, not a mystery.

## `ci/check.mjs`

```
node ci/check.mjs
```

Everything that must hold before the package ships — four checks, each
earned by a specific way the fleet's error handling failed. The healthy
run, verbatim:

```
ok    generated code matches the catalogue
ok    schema and catalogue name the same codes
ok    schema and catalogue name the same severities
ok    the failure point pattern is stated once
ok    every golden envelope obeys the schema
ok    runtimes agree (11 case(s) + 45 vocabulary row(s), 0 failing)

all checks passed
```

Exit 0; any failing check prints `FAIL` with the detail indented under it,
ends with `<n> check(s) failed`, and exits 1. Check 3 is a hand-rolled
schema validation over exactly the fields `failure.schema.json` uses —
required keys, no unknown keys, the failure-point grammar (a malformed
point is allowed only when `context` records
`wisent_errors.failure_point: malformed`), derived fields re-derived from
the catalogue, and no empty `service`/`impact`/`detail` strings. What each
failure looks like is in the [runbook](../runbook.md).

## `tests/conformance.mjs`

```
node tests/conformance.mjs
```

Proves the four runtimes are one behaviour. It builds the Rust and Swift
emitters itself (`cargo build --quiet --bin emit`, `swift build`) — a
harness that reports RUNTIME MISSING on a fresh clone teaches people to
read past that line — then has every runtime emit every golden case in
`tests/conformance/cases.tsv` and dump the derived vocabulary probed by
`tests/conformance/table.tsv`, comparing everything against the expected
column and against each other. Healthy output is one `ok` line per case
naming the runtimes that agreed, one for the vocabulary, and the summary:

```
ok    credential-refused  (js, python, rust, swift)
...
ok    derived vocabulary  (45 rows, js, python, rust, swift)

11 case(s) + 45 vocabulary row(s), 0 failing
```

Failure vocabulary: `FAIL <case>` with the expected and differing lines,
`RUNTIME MISSING <label>` when an emitter could not run, `TABLE DIFFERS
<label> vs <reference>` with up to five differing rows, `TABLE MISSING
<label> -- <why>`. Exit 0 only when nothing fails. One caveat worth
knowing: the trailing `ok    derived vocabulary` line records only that
all four runtimes *dumped* a table — `TABLE DIFFERS` lines above it are
the verdict, and they are counted in the summary.

## `ci/no-handrolled-envelope.mjs` — the guard

```
node ci/no-handrolled-envelope.mjs <path> [<path>...]
```

Run by consumers against their own tree. Reports every line outside this
package that writes a `failure_point` or `error_code` key — quoted or
bare, key (`:`) or assignment (`=`) — in `.rs .py .mjs .js .ts .tsx .jsx
.go .swift .sh` files, skipping `node_modules target .git dist build .venv
__pycache__ vendor`. Clean:

```
no hand-built envelope in /tmp/toy-shelf
```

exit 0. Findings, captured against a toy tree:

```
2 site(s) name an envelope key outside the package:
  /tmp/toy-shelf/serve.mjs:14  failure_point: 'shelf.store.read',
  /tmp/toy-shelf/serve.mjs:15  error_code: 'store_down',

Each needs a reason. Building an envelope here means the derived fields can be
wrong, so build it with wisent-errors instead. Three answers are legitimate and
common: an operator-visible log line whose format is already parsed, a field
declaration, and another API's own `error_code` -- Azure has one, and this guard
cannot tell it from ours. Read the line before believing the count.
```

exit 1. No path given: the usage line and exit 2. It reports sites, not
verdicts — read the line before believing the count.

## `ci/find-implementations.mjs` — the census

```
node ci/find-implementations.mjs [<root>...] [--unadopted-only]
```

Default root: the parent of this repository. Two passes. The literal scan
finds files quoting `infra_down` (the one code that is not an English
phrase) plus at least four of the seven codes as string literals — that
calibration reproduced exactly the nineteen implementations found by hand
and nothing else. The manifest sweep reads `package.json`, `Cargo.toml`,
`Package.swift`, `pyproject.toml`, `setup.py`, `requirements.txt` for a
dependency on the package and extracts the pinned sha near the package
name. Checkouts of one remote are merged; a file that no longer restates
the vocabulary at `origin/HEAD` demotes its checkout to `stale`, and a
checkout with no remote at all is `detached` — neither counts against the
census. Captured against a toy fleet (one legacy clone, one adopted
repository):

```
RESTATES  toy-fleet/toy-legacy  (1 file(s))
         src/failure.mjs  names 7/7

declares  toy-fleet/toy-adopted  pin b01a0c9c

1 checkout(s) declare a dependency on the package.
1 still quote four or more codes as literals: 1 restate the taxonomy, 0 are stale or detached copies of one that does not, 0 are part-migrated and name the package too.
```

Row labels: `adopted` (quotes codes but also names the package —
part-migrated), `RESTATES` (a live copy of the vocabulary), `stale`,
`detached`, and `declares` rows for the manifest sweep (`pin unpinned`
when no sha is found and the dependency is not `workspace = true`). Exit 0
only when no live checkout restates the taxonomy. What neither pass can
find, stated so nobody trusts the tool further than it goes: a module that
generates or interpolates the code strings instead of writing them out.

## Where they run

`check` (which runs `generate --check` and `conformance`) gates this
repository; the guard and the census run against consuming trees —
adoption strategy in [integration](../integration.md), a worked migration
in [walkthrough-adoption](../walkthrough-adoption.md), the healthy gate
run in [walkthrough-conformance](../walkthrough-conformance.md).
