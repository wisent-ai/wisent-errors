# Layout, and how it stays one thing

Where each part of the package lives, and the check that keeps the catalogue,
the schema and the generated runtimes saying the same thing.

## Layout

```
catalogue/codes.json          the single source of truth
schema/failure.schema.json    the envelope, checkable from any language
codegen/generate.mjs          one generator, three targets
rust/    crate   wisent-errors   (rust/src/operation.rs: a functionality's declared causes; rust/src/warning.rs: its declared warnings)
python/  package wisent_errors
js/      package @wisent/errors  (+ .d.ts, four consumers are TypeScript; js/warning.mjs: declared warnings)
swift/   library WisentErrors    (two native clients: oko-desktop, wisent-ios)
ci/check.mjs                  what must hold before this ships
ci/no-handrolled-envelope.mjs the guard a consuming repo runs
ci/error-standard.mjs         the lint a consuming repo runs: generic sentences, functionality catalogues, their tests and entries
ci/warning-standard.mjs       the lint a consuming repo runs: declared warnings, their tests, and one warning for every confirmation
ci/tests-held.mjs             whether a repository holds the test a cause or a warning names
tests/warnings/               standard.mjs (node --test) and declaration.rs (cargo test --test warnings)
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
```

The generated runtimes are written from the catalogue by one generator, so
the first line is what keeps the four of them one vocabulary.

The second guard, `ci/no-handrolled-envelope.mjs`, is the one a consuming
repository runs against its own tree; the README shows what it prints when it
finds a hand-built envelope.
