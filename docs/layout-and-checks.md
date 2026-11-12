# Layout, and how it stays one thing

Where each part of the package lives, and the check that keeps the catalogue,
the schema and the generated runtimes saying the same thing.

## Layout

```
catalogue/codes.json          the vocabulary, the single source of truth
catalogue/declaration.json    what a declared cause or warning must be, and every sentence refusing one
catalogue/failures/           this package's own failures, one part per area (read by codegen/parts.mjs), telemetry's included
schema/failure.schema.json    the envelope, checkable from any language
codegen/generate.mjs          one generator, four runtimes and docs/errors/
rust/    crate   wisent-errors   (src/operation/: causes and templates; src/warning.rs: warnings; src/invalid.rs: why an envelope was refused; src/failures/: generated, one module per part of catalogue/failures/; src/telemetry/, feature `telemetry`: consent, queue, delivery, export)
python/  package wisent_errors   (operation.py, template.py: the same declarations and rules)
js/      package @wisent/errors  (+ .d.ts; operation.mjs, template.mjs, warning.mjs, refusal.mjs)
swift/   library WisentErrors    (Operation.swift, Warning.swift, Template.swift, Invalid.swift, Report.swift; OwnFailures*.swift: generated, one file per part; Telemetry*.swift: the same telemetry as the Rust feature) and WisentTelemetryUI (the Settings section)
ci/check.mjs                  what must hold before this ships, this package's own catalogue included
ci/no-handrolled-envelope.mjs the guard a consuming repo runs
ci/error-standard.mjs         the lint a consuming repo runs: generic sentences, functionality catalogues, their tests, the values their raising sites pass, their entries
ci/warning-standard.mjs       the lint a consuming repo runs: declared warnings, their tests, and one warning for every confirmation
ci/refuse.mjs, input.mjs, arguments.mjs  how these commands refuse, read their files and read their words
tests/<area>/                 declaration, envelope, cli-output, lint, tools, warnings, telemetry; tests/untested-causes.json lists what no local state provokes
```

Generated files are committed, so a consumer needs no build step, and
`ci/check.mjs` fails if they drift from the catalogue, or if a generated
module or page remains that no part of `catalogue/failures/` writes any more
(`STALE`); `node codegen/generate.mjs` removes it.

## How it stays one thing

```
$ node ci/check.mjs
ok    generated code matches the catalogue
ok    schema and catalogue name the same codes
ok    schema and catalogue name the same severities
ok    the failure point pattern is stated once
ok    this package's own node failure catalogue holds (12 functionalities)
```

The generated runtimes are written from the catalogue by one generator, so
the first line is what keeps the four of them one vocabulary and one set of
declaration rules; each runtime's tests check its template reading against
the probes catalogue/declaration.json states.

The second guard, `ci/no-handrolled-envelope.mjs`, is the one a consuming
repository runs against its own tree; the README shows what it prints when it
finds a hand-built envelope.

## The lint a product runs

`ci/error-standard.mjs` holds a product's tree to the same standard:

```
$ node ci/error-standard.mjs scan ../stado/stado-rs/src
Error: holding ../stado/stado-rs/src/cli/workload/runners/weles/browser.rs to the error standard: line 295 says "did not succeed", ...
$ node ci/error-standard.mjs catalogue catalogue.json --repository ../stado --entries entries.json
ok    stado.fleet.enroll: 21 declared cause(s)
```

`scan` refuses an error message holding one of the catalogue's
`generic_sentences` inside a string literal; a baseline lets a product adopt
the rule before every old message is rewritten, and may only shrink.
`catalogue` applies the declaration rules to the JSON a product's `errors list
--json` prints, whatever language declares it. With `--repository` it also
reads the repository: each cause's test is written, or listed in the
repository's `tests/untested-causes.json` (`[{"test": ..., "reason": ...}]`)
with why no local state provokes it; and each placeholder is passed by some
raising site, read from the source (`("name", value)` in Rust, a `name:` key in
JavaScript, a `"name":` key or `name=` keyword in Python, a `"name":` key in
Swift), so `{fleet}` that no site passes is refused at the declaration instead
of reaching a reader as `{fleet}`. The whole repository but its tests is read,
or the paths `--sources a,b` names. With `--entries`, an entry no
functionality names is refused. `node ci/error-standard.mjs errors --json`
prints this package's own catalogue; every refusal of these commands is one
of its causes, listed on [errors/](errors/).

Warnings are declared beside causes: [warnings.md](warnings.md).
