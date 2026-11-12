# Changelog

## Unreleased

### `ci/check.mjs` runs the node tests

- Nothing ran this package's node tests before a push, which is how six failing
  ones reached main unseen. `node ci/check.mjs`, what must hold before this package
  ships, now runs every `tests/<area>/*.mjs` with `node --test` and fails naming each
  failing test (`the node tests pass (14 files)`).

### The guards read the trees their own tests make, and every node test passes

- `ci/no-handrolled-envelope.mjs` and `ci/find-implementations.mjs` skipped every
  file under the package's own folder, so the trees their tests write under
  `target/real-tests` were never read: the guard reported a clean tree and the census
  found nothing (`a_hand_built_envelope_is_listed` and the three census cases failed),
  and a sibling folder whose name only began like the package's was skipped too. Both
  now ask `packageSource` in `ci/input.mjs`: the package's own source, by resolved
  path, but not what a build or a test writes under `target/` or `.build/`.
- `node ci/error-standard.mjs catalogue --entries` printed an entry no functionality
  starts as one bare sentence; it is the declared refusal, `Error:`, `fix:` and
  `cause:`, like every other refusal the lint lists.
- `a_use_no_part_declares_is_refused` replaced a uses list `tools.json` no longer
  holds, so the catalogue stayed valid and the case failed; it edits the census's
  list and fails at once if its edit changes nothing. `node --test` over `tests/lint`,
  `tests/tools`, `tests/declaration`, `tests/envelope` and `tests/warnings`: 62 of 62.

### Every Swift app reads JSON through one described decoding

- `WisentErrors` exports `JSONDecoder.decodeDescribed`, which throws
  `DescribedDecodingError` ("`<Type>` could not be decoded: `<reason>`", the reason
  `Error.explained` says for the `DecodingError` it carries), and
  `JSONSerialization.describedObject`, which throws `DescribedJSONError` with the
  character and position Foundation stopped at. Thirteen apps keep their own
  `DescribedDecoding.swift`, copies that drift in wording and wrapping; an app that
  depends on this release drops its copy for this one. Real tests:
  `tests/explained/DescribedTests.swift` (`swift test --filter DescribedTests`).

### Every Swift app says a failure through one `Error.explained`

- `WisentErrors` exports `Error.explained`: a declared description as declared, a
  `DecodingError` with the coding path it stopped at, a Cocoa error with its domain and
  code, any other error as its type and value, then each underlying error, read until the
  chain ends or repeats. Twenty-six apps keep their own `ExplainedError.swift`, copies that
  drift only in wrapping; an app that depends on this release drops its copy for this one.
  Real tests:
  `tests/explained/ExplainedTests.swift` (`swift test --filter ExplainedTests`).

### The generator writes Rust without rustfmt

- `node codegen/generate.mjs` wrote each Rust module through `rustfmt` so the push gate's
  `cargo fmt --check` agreed with it; no Wisent repository runs rustfmt or a format gate any
  more, so the modules are written as the renderers lay them out, and the three refusals that
  formatting could raise (`edition-undeclared`, `rustfmt-absent`, `rustfmt-refused`) are gone with
  their tests. The regenerated crate builds with kompilator and `--check` finds no drift.

### Declarations say everything a reader needs, in every runtime

- `fill` read `{value:?}` as a placeholder named `value:?`, never filled it and
  left it in the sentence, and `Cause::problems` accepted it. The four
  runtimes now read a template the same way (`parts`: a placeholder is
  `{name}`, a lowercase letter then lowercase letters, digits and `_`), and
  every placeholder the renderer will not fill is refused at the declaration,
  naming the cause, the field, the placeholder and the name to write: a format
  spec, an upper-case or dotted name, a `{` nothing closes, a `}` nothing
  opened.
- A cause whose `cause` is only the text it wraps (`{error}`, `{code}:
  {reason}`) is refused, and a raw-message placeholder (`{error}`,
  `{problem}`, `{message}`, `{body}`, `{stderr}`, ...) is refused in `failed`,
  `cause` and `remedy`: it belongs in `observed`.
- `node ci/error-standard.mjs catalogue --repository` refuses a placeholder no
  raising site of the repository passes, reading `("name", value)`, `name:`,
  `"name":` and `name=` in the source (`--sources` names where to read), and
  accepts a cause whose test cannot be written locally when
  `tests/untested-causes.json` lists it with the reason.
- `Cause::failure` records a placeholder the raising code gave no value for
  in `context["wisent_errors.unfilled"]`.
- The rules and every sentence that refuses a declaration are one schema,
  `catalogue/declaration.json`, generated into `rust/src/declaration.rs`,
  `js/declaration.mjs`, `python/wisent_errors/declaration.py` and
  `swift/Sources/WisentErrors/Declaration.swift`. Python and Swift gain
  `Cause`, `Operation`, `fill`, `placeholders`, `unfilled`,
  `template_problems` / `templateProblems`, `problems` and
  `catalogue_problems` / `catalogueProblems`; Python gains `Warning` too.
  Every refusal sentence now ends with what fixes it.

### This package's own failures are declared

- `catalogue/failures/` declares every way this package's functionalities
  fail, one part per area, read by `codegen/parts.mjs` and generated into each
  runtime's own catalogue (`rust/src/failures/`, `js/failures.mjs`,
  `python/wisent_errors/failures.py`,
  `swift/Sources/WisentErrors/OwnFailures*.swift`) and onto `docs/errors/`.
  `node ci/error-standard.mjs errors --json` prints it; `node ci/check.mjs`
  holds it to the rules it gives every product.
- `Failure::new`, `failure()` and `Failure(failurePoint:code:service:)` name
  the segment and the character a malformed failure point breaks the grammar
  with, a point that would pass, and the fallback; `Invalid` carries the
  service, the given text and the point. `failure()` in JavaScript and Python
  raises a `DeclaredError` (still a `TypeError`) naming the operation and the
  cause. The fallback builders record the cause in
  `context["wisent_errors.failure_point_cause"]`. Rust's grammar now refuses
  `a-_b` as the pattern always did.
- `cli_output::read_json` says whether the file is absent, a directory, not
  readable, not JSON (line, column and the line itself), cut short, or JSON of
  the wrong shape (and the type it was read as); `cli_output::output` returns
  a declared refusal for a result JSON cannot hold and for a closed or full
  standard output instead of panicking.
- The commands under `ci/`, `codegen/generate.mjs` and `tests/inventory.mjs`
  refuse through declared causes: `no-handrolled-envelope` and
  `find-implementations` no longer report an absent or unreadable tree as
  clean, `find-implementations` refuses a file it cannot read and a census
  with no git, `inventory` names a revision git does not know, a pattern it
  does not read and a checkout that is no repository, and the generator names
  a manifest without an edition, a missing or refusing rustfmt and a file it
  cannot write.
- `docs/examples/rust-consumer.sh` builds its consumer under the checkout's
  ignored `.build/`, not under `$TMPDIR`.
- Telemetry reads the home the environment names (`HOME`) in Swift as in
  Rust, never the account's home behind it, and a caller can name the
  directory itself: `Telemetry::in_directory(product, dir)` in Rust,
  `WisentTelemetry(product:environment:)` in Swift, and
  `WisentFailureReporter(telemetry: nil)` reports nothing. The tests name
  their own directories, and a Swift delivery case without its collector
  fails naming it instead of being skipped. The Rust, JavaScript and Python
  runtimes ship no reporter, so none of them reads a home or posts anywhere.
- Every telemetry refusal is a declared cause of
  `catalogue/failures/telemetry.json`, generated into Rust
  (`rust/src/failures/telemetry.rs`) and Swift
  (`OwnFailuresTelemetry.swift`) by `codegen/generate.mjs`, so the two
  runtimes cannot drift: the hand-written `rust/src/telemetry/causes.rs`
  tables and `TelemetryCauses.swift` are gone. A part may give `entries` one
  list per runtime, like `tests`; Rust and Swift get one generated module per
  part (`rust/src/failures/`, `OwnFailures<Area>.swift`) with `uses`
  rendered, and Swift raises each cause by its generated name
  (`OwnFailures.envelopeBuildServiceAbsent`), never by an id it unwraps. The
  files' causes are one layer (`wisent-errors.telemetry.store`, which
  `telemetry::operations()` and `WisentTelemetry.operations` list): no
  directory named, a directory that cannot be written with the step refused
  and what stands at its path, a state file that cannot be read (mode and
  owner), is not JSON (line and column) or is no object, a queue that cannot
  be listed, a consent naming no known level (with what stands at its path), a
  terminal that refuses the answer, no randomness for an id. A collector
  address names what is wrong with it. An installation file naming no id is
  said (`installation-id-absent`) and `status` shows it, instead of being
  replaced in silence. `Telemetry::export` to a path that cannot be written
  says the export's own path (`wisent-errors.telemetry.export`,
  `export-unwritable`), not the telemetry directory and its
  `WISENT_TELEMETRY_HOME`. A refusal's why is its own words, the collector's
  answer and the transport's error only what it observed; `status` shows an
  unreadable installation id or last delivery instead of hiding it, and
  `spawn_flush` says an unreadable consent or invalid collector.
- `node codegen/generate.mjs --check` counts a generated module or page no
  part writes any more as drift (`STALE`), and generating removes it, refusing
  one it cannot remove (`generated-unremovable`, with its directory's mode).
  rustfmt runs in the crate's directory, so a module directory not made yet is
  no longer reported as a missing rustfmt.
- Swift declares warnings like the other runtimes: `Warning`, `Hazard`,
  `Operation(..., warnings:)`, `unconfirmed`, `warningsJSON(page:)`,
  `warningsMarkdown()`.
- The listing problems of `error-standard catalogue` and
  `warning-standard` are sentences of `catalogue/declaration.json`, each
  naming the operation, the value found and the one to print; a file that is
  not JSON names the line and column the decoder stopped at; the census names
  each restating repository's files and how many codes each quotes.
- `docs/examples/swift-consumer.sh`, which drove the reporter against a toy
  Probierz intake the reporter no longer posts to, is gone.
- The README moved its history to `docs/history.md`, warnings to
  `docs/warnings.md` and pinning to `docs/pinning.md`, so no file passes 300
  lines.
