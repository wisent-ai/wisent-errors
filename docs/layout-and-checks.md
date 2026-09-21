# Layout, and how it stays one thing

Where each part of the package lives, and the check that keeps four runtimes
saying the same thing. This was part of the README until 2026-09-21, when that
file stood at 485 lines — past the three-hundred-line limit every file in this
workshop lives under.

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

The second guard, `ci/no-handrolled-envelope.mjs`, is the one a consuming
repository runs against its own tree; the README shows what it prints when it
finds a hand-built envelope.
