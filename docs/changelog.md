# Changelog

## Unreleased

### A catalogue page names a usage cause by the class its refusal prints, `usage`

- `Operation::markdown` is what `stado errors show --markdown` prints. It
  said a usage cause under its declared code (`Code: config, exit 2`),
  which reads as a misconfigured deployment when the refusal is the
  command line's own. It now prints `Class: usage, exit 2; retrying
  unchanged will not help`, and every other cause's line reads `Class:
  <code>`.
- The class comes from `wisent_errors::Class`, the one source: `Class::of`
  gives `usage` for a usage cause whatever code it carries, otherwise the
  code, with its `as_str`, `retryable`, `severity` and `summary`.
  `wisent_errors::operation::USAGE_SUMMARY` is its usage summary. Stado's
  `primitives::failure::Class` can re-export it and keep only its own line
  format.
- The generated pages docs/errors/*.md (codegen/pages.mjs) print the same
  `Class:` line.
- `wisent-errors errors page` prints the command's own catalogue as
  `Operation::markdown` renders it. `tests/errors/page.rs` compares the
  whole page with one rendered from catalogue/failures on disk. That
  catalogue holds usage causes declared `refused` and `not_found`. The new
  gate is `rust-errors-page`.

### A product's CI holds its doctor and its warnings to the rules through `wisent-errors doctor check` and `warnings check`

- `wisent-errors doctor check <errors-list.json> <doctor.json>` holds the
  findings a product's `doctor --json` printed to the functionalities its
  `errors list --json` declares, through `diagnosis::problems`. It refuses
  a functionality with an entry point and no check, one checked twice, and
  a check of one the catalogue does not declare as
  `wisent_errors.command.check.doctor-incomplete`, each problem numbered.
- `wisent-errors warnings check <warnings-list.json>` holds each warning a
  product's `warnings list` printed to the declaration rules: a warning
  declared twice, an empty field, a malformed test path, and an unknown
  hazard (read with `Hazard::parse`). It refuses them as
  `wisent_errors.command.check.warnings-invalid`.
- A file either command cannot read is refused as
  `wisent_errors.cli_output.read_json` refuses it. A document that is not
  what the named command prints is refused as `input-shape-invalid`, naming
  the place and what it holds.
- `wisent-errors errors list` prints the command's own failure catalogue.
- `Operation::warning_problems` is public: the warning lines of
  `Operation::problems` alone, which `warnings check` uses. It replaces the
  crate-private `declaration_problems`.
- These rules lost their in-process Rust tests when the tests moved onto
  the binary. They are tested again through it:
  `tests/diagnosis/main.rs::doctor_check_holds_the_findings_to_the_errors_list`
  and
  `tests/warnings/declaration.rs::warnings_check_holds_each_warning_to_the_declaration_rules`.

### `wisent-errors-swift`, the Swift package's command line, and the Swift tests run it as a process

- `Package.swift` ships an executable, `wisent-errors-swift`
  (`swift/Sources/wisent-errors-swift`), driving the three libraries the way
  an app drives them: `envelope build|read`, `declaration cause|check`,
  `telemetry status|set|failure|show|flush|settings`, `support
  report|status` and `program run <name> [-- <arguments>]`, which runs an
  installed program through `WisentProgram`, hands its output on as it
  comes, stops its whole process group on SIGTERM or SIGINT and kills it on
  a second. Its refusals are printed in the three lines of the package's
  other commands and exit with the cause's status; its own are declared in
  `catalogue/failures/swift-cli.json` (`wisent_errors.swift_cli.arguments`,
  `input`, `envelope_build`, `declaration_cause`, `declaration_check`,
  `settings_window`, `program_run`). docs/guides/swift-reporter.md lists
  every command.
- Every Swift test runs it as a process, from the products directory `swift
  test` builds it into (`tests/swift-cli/CommandCase.swift`), its environment
  cleared and given only `HOME`, `TMPDIR`, `XDG_*` and the product's own
  variables inside a directory of the case's own under `.build`: one test per
  command and its story, the exit status, the whole refusal and the files on
  disk read back after each step. The Swift test targets are one,
  `WisentErrorsTests`, depending on the executable. Admission is checked
  against real files' real signatures (an unsigned script, a copy of
  `/bin/sh`, the fleet's stado under another product's name), the settings
  window is driven through the Accessibility API, and the collector and
  support stay the real ones, named by the same variables. Each Swift
  `tests` pointer in `catalogue/failures/` names the test that now provokes
  its cause; a file read stopped part way and a run whose end cannot be
  followed, which no input provokes, are listed in
  `tests/untested-causes.json`.

### Telemetry and support errors carry their declared refusal whole

- `TelemetryError`'s `unwritable`, `unreadable` and `collectorInvalid` and
  every `SupportError` case carried the refusal as one joined sentence, so a
  command could print it only as that line. Each now carries a
  `DeclaredRefusal` (the functionality, the cause and the values its
  sentences name), whose `description` is the same sentence, `lines` the
  three lines a command prints and `exitCode(failureExit:)` the cause's
  status; `TelemetryError.refusal`, `SupportError.refusal`,
  `Invalid.refusal` and `WisentTelemetry.Delivered.refusal` hand it on. A
  consumer matching `.unwritable(let sentence)` reads `refusal.description`.

### A failure reported under a damaged consent file says so

- `WisentTelemetry.failure` read a consent file telemetry did not write as
  no answer and queued nothing without a word. It still queues nothing, and
  now says the file's own refusal on stderr, naming the file, what it holds
  and how to answer again.

### `wisent-errors`, the crate's command line, and its tests run it as a process

- The Rust crate ships a program, `wisent-errors` (`[[bin]]`, built with
  `cli-output`, `telemetry` and `diagnosis`): the `telemetry status|level|on|
  off|failure|command|help|show|events|export|flush` and `support
  report|status` commands every product CLI carries from the crate, run for
  the product a JSON file named with `--product` describes (`id`, `app_id`,
  `version`, and optionally the `flush` command started in the background
  after a reported failure or command), a `doctor` over those
  functionalities, and `warnings list|page`. A result is printed through
  `cli_output::output`; a refusal is the three lines every command of the
  package says, its cause a declared one, its exit status the cause's.
  docs/command-line.md is its page.
- Its own refusals are declared in `catalogue/failures/command.json`
  (`wisent_errors.command.arguments`: no command, an unknown one, a missing
  or extra operand, an unknown option, an option without its value, a
  number or a code it cannot read; `wisent_errors.command.product`: no
  product file, or a field of it that is not what it should be).
- `tests/telemetry/`, `tests/diagnosis/main.rs` and
  `tests/warnings/declaration.rs` no longer call the library: each runs the
  program with its environment cleared and a home of the case's own under
  `CARGO_TARGET_TMPDIR`, one test per command and its refusals, and reads
  the exit status, the whole refusal and the store on disk back after every
  step. The collector and support they reach stay the real ones, named by
  the same variables. `tests/cli-output/print.rs` is one test of the print's
  whole story. Each Rust `tests` pointer in `catalogue/failures/` names the
  test that now provokes its cause; the diagnosis's
  `probe-failure-unexplained`, which only a product's own probe code meets,
  is listed in `tests/untested-causes.json`.

### An export that cannot be written names the file, not the telemetry directory

- `Telemetry::export` (`telemetry export <file>`) refused a file it could not
  write as `store-unwritable`, saying the telemetry directory could not be
  written and telling the user to make it writable or set
  `WISENT_TELEMETRY_HOME`, neither of which helps. It is now its own cause,
  `wisent-errors.telemetry.export.export-unwritable`: the file, how many
  events, what the system answered and what is where the file would go,
  fixed by naming a file in a directory the user can write; the events stay
  queued. `telemetry::operations()` lists the export.

### A collector's or support's answer quoted in a refusal stays on one line

- A refusal quoting an answer that was not the collector's or support's (a
  `robots.txt`, an HTML error page) carried the answer's line ends into its
  sentence, so a command's three-line refusal broke into many. The answer
  is now quoted on one line: JSON as its compact form, anything else as a
  JSON string.

### Each node command's test tells its whole story as a process with a cleared environment

- Every node command of the package has one test of its whole story: its
  success and each refusal it gives, one step each, started with
  `process.execPath` in a case directory under `target/real-tests/`, with
  the environment cleared to PATH and a HOME, TMPDIR and XDG_* inside the
  case. After every step the test asserts the exit status and the whole of
  stdout and stderr, then reads the case's files back byte for byte and its
  home back empty. The tests are `tests/lint/scan.mjs`,
  `tests/lint/catalogue.mjs`, `tests/lint/input.mjs`, `tests/lint/paths.mjs`,
  `tests/lint/arguments.mjs`, `tests/guard/handrolled.mjs`,
  `tests/warnings/standard.mjs`, `tests/tools/errors.mjs`,
  `tests/tools/parts.mjs`, `tests/tools/census.mjs`,
  `tests/tools/inventory.mjs` and `tests/tools/generate.mjs`.
  `tests/ship/check.mjs` runs `node ci/check.mjs` on a copy of the package
  whose schema names a code the catalogue lacks. Each cause's `js` test
  pointer in `catalogue/failures/` names the test that now provokes it.
- `node codegen/generate.mjs` reads its words through
  `wisent_errors.lint.arguments`, as every other command does. A misspelt
  `--chek` was ignored, so the generator wrote the files it had been asked
  only to compare. Now an option it lacks is refused with `option-unknown`
  and an operand with `operands-miscounted`, each naming
  `node codegen/generate.mjs [--check]`.
- A JSON input whose decoder stopped at an unexpected token now has its
  line and column named. V8 gives no position for such a token, only the
  text around it, so the refusal read "a place the decoder did not name".
  The quoted text's line breaks are written as `\n`, so the refusal keeps to
  its three lines; a catalogue part that is not JSON says its decoder answer
  on one line too.
- A `scan` baseline of the wrong shape names the entry that breaks it: a
  path holding a number instead of its sentences, or a count that is not a
  number.
- A `--sources` path of `catalogue` that does not exist is refused as
  `path-absent`, naming the directory meant to hold it. It used to be
  `path-unreadable`, whose `chmod` cannot fix a typo.
- `codegen/parts.mjs` points the loader's causes a part on disk can provoke
  at `tests/tools/parts.mjs::errors_reads_every_part_or_refuses_the_one_it_cannot`.

### The declaration rules are tested through the command a product's CI runs, in node

- `tests/declaration/placeholders.py` is gone: it called the Python
  runtime's template internals in-process, and the gates run no Python.
  `tests/declaration/listing.mjs` takes its story: a product's listing,
  printed through `catalogue`, is run through `node ci/error-standard.mjs
  catalogue` as a process. It covers each placeholder, raw-message and
  test-path probe of catalogue/declaration.json. For each it asserts the
  whole output and exit status, then reads the listing back unchanged and
  the case's HOME and TMPDIR empty.
- `tests/envelope/build.py` is gone too: no gate may run Python. Each
  envelope refusal it provoked in the Python runtime is provoked, with the
  same catalogue sentence, by `tests/envelope/build.mjs`, and the
  failure-point and service ones also by `tests/envelope/build.rs` and
  `wisent-errors-swift envelope build`
  (`tests/envelope/EnvelopeBuildTests.swift`). Its nine `python` pointers
  stay in catalogue/failures/envelope.json, so the Python runtime keeps those
  causes, and are listed in tests/untested-causes.json with that reason. The
  Python runtime's raising code (`failure`, `raise_failure`,
  `failure_or_fallback`) has no test until a gate runs Python;
  `python/wisent_errors/failures.py` is still held to the catalogue by
  `node codegen/generate.mjs --check`.

### The gates are handed the stado, node and collector the Swift cases run

- `.wisent-release.json` declares what every queued gate's run is given:
  Stado's CLI as a test product, `WISENT_PROGRAM_TEST_STADO` and
  `WISENT_PROGRAM_TEST_NODE` naming that stado and the Node.js release Stado
  links into the run's home (`~/.local/bin/stado`, `~/.local/bin/node`), and
  `WISENT_TELEMETRY_TEST_COLLECTOR` and `WISENT_TELEMETRY_TEST_APP_ID` naming
  the public Echo collector and `wisent-telemetry-test`, the app
  echo-deployment's `sources/apps.json` declares for these cases. The
  WisentProgram cases failed every gate with `WISENT_PROGRAM_TEST_NODE is not
  set`. A collector that fails on its side
  (`WISENT_TELEMETRY_TEST_FAILING_COLLECTOR`) and a support service whose agent
  API a gate reaches (`WISENT_SUPPORT_TEST_URL`,
  `WISENT_SUPPORT_TEST_AGENT_TOKEN`) exist nowhere a gate host reaches, so
  `ReachedDeliveryTests`' failing-collector case and `SupportServiceTests`
  still name their variable.

### The manifest's test comment names kompilator

- `rust/Cargo.toml` says the `cli_output`, `telemetry` and `diagnosis` tests
  run in every `kompilator test`.

### The tools journeys keep their temporary files in their own case

- `tests/tools/census.mjs` and `tests/tools/inventory.mjs` run git and the
  tools with `TMPDIR` set to the case's own home under `target/real-tests`,
  as they already set HOME there, so nothing they start writes to the system
  temporary directory.

### A JSON input of the wrong shape is refused in words, not by a Rust type

- `cli_output::read_json`'s `input-wrong-shape` refusal named the Rust type
  the input was decoded into (`alloc::vec::Vec<crate::Record>`), which a
  person running the command cannot act on. It now names the file and the
  line and column where the decoder stopped, and its fix is to give that
  place the value the decoder answered it expected there.
  `ReadJsonError::Parse` no longer carries `expected`.

### Every command's tests compare the whole refusal, and success paths are tested

- The tests of `ci/error-standard.mjs` (`scan`, `catalogue`, `errors`),
  `ci/warning-standard.mjs`, `ci/no-handrolled-envelope.mjs`,
  `ci/find-implementations.mjs`, `codegen/generate.mjs` and
  `tests/inventory.mjs` compare each run's whole stdout and stderr and its
  exit status, with what the operating system, git and the decoder answer
  read by asking them the same way, instead of matching a part of a
  sentence. New cases cover what passes: a clean tree and an allowed
  baseline for `scan`, `--sources` and an entry the inventory lacks for
  `catalogue`, the package's own listing for `errors`, an adopted, a stale
  and a detached checkout for the census, the listed lines of a committed
  revision for the inventory, a written-back file for the generator, and a
  clean tree, a clean file and the package's own source for the guard.
- The guard's test moved to `tests/guard/handrolled.mjs`; the Rust delivery
  tests are split into `tests/telemetry/delivery/reached.rs` and
  `unreached.rs`, and the queue's into `tests/telemetry/queued/`, so no test
  folder holds more than five files. The catalogue's test pointers name the
  new files.
- Delivery, consent and support refusals are compared whole in Rust, the
  collector's and support's own words being the one part read as part; an
  unreachable collector or support is the discard port on loopback.
- Each runtime's envelope tests build a whole envelope, render and chain it,
  and salvage a malformed one, beside the refusals.
- A Python field that is not text was told to pass `String(error.message)`,
  JavaScript's spelling; `field-not-text` now names each runtime's own
  (`{conversion}`: `String(error.message)` in JavaScript, `str(error)` in
  Python).
- A telemetry file the operating system refuses to read (no permission, a
  directory in its place) was refused in Rust as "not what telemetry wrote"
  holding 0 bytes, and thrown in Swift as the bare system error. Both now
  refuse with the declared `wisent-errors.telemetry.store.file-read-refused`,
  naming what is at the path and what the operating system answered.
- A Swift flush read a damaged consent file as unanswered and said nothing;
  it now stops with the file's own refusal, kept in `delivery.json`.
- A census or inventory with no git to start said `PATH ;` for an empty
  PATH; it now says `PATH holds ""`, or `PATH is unset`.
- The generator's refusal of a generated file it may not read names the
  file by its absolute path, so its `chmod u+r` works from any directory;
  the fixes of `generated-unwritable` and `generated-unremovable` name the
  file and its directory by absolute path too (`{target_path}`,
  `{directory_path}`), while what failed keeps the repository-relative name.
- A diagnosis probe failing with an envelope that carried no detail or no
  remedy was printed with filler ("it failed and said nothing more", "no
  remedy is declared"). `diagnosis::diagnose` now refuses it with the
  declared `wisent_errors.cli_output.diagnose.probe-failure-unexplained`,
  naming the functionality, what the envelope lacks, its point and its code;
  `State::Fails` holds a `Failed` whose detail and remedy are always said.
  A consumer matching `State::Fails(failure)` reads `failed.failure()`,
  `failed.detail()` and `failed.remedy()`.
- Echo's collector answers an undeclared app with its declared cause
  `app-undeclared`, so `collector-refused`'s fix names that cause, where it
  named the words "Unknown mobile analytics app" Echo no longer says; the
  Rust test compares the collector's operation, cause, sentence and fix
  whole.
- The package's own failure catalogue may keep parts in subfolders of
  `catalogue/failures/`: `codegen/parts.mjs` reads every `.json` at any depth
  in path order and refuses a subfolder it cannot list with `parts-unlisted`
  naming it. The lint parts moved to `catalogue/failures/lint/commands.json`
  and `lint/layers.json`, so no catalogue folder holds more than five files;
  a generated banner names each part by its path below `catalogue/failures/`.

### `WisentProgram` runs only the program the fleet signed

- `InstalledProgram` ran the program the product's variable named, else the
  first on `PATH`, else `~/.local/bin` or `~/.stado/bin`, checking only that
  the file was executable: any process of the user's account could set the
  variable, or put a stand-in first on the login `PATH`, and be handed the
  product's finance, health or legal data and its serve token (audit
  2026-11-17, audit-rest-01.md row 39). It now looks only in
  `~/.local/bin/<name>` and `~/.stado/bin/<name>`, and both the file found
  and the process the kernel started from it must meet
  `identifier "com.wisent.<name>" and anchor apple generic and certificate
  leaf[subject.OU] = "LNTWB5B9DV"`: the program is spawned suspended
  (`POSIX_SPAWN_START_SUSPENDED`), checked by pid (`SecCodeCopyGuestWithAttributes`,
  `SecCodeCheckValidity`), checked to be still stopped with no user time
  (`proc_pidinfo`, `proc_pid_rusage`: any process of the account may resume
  a suspended child early) and resumed only once admitted, so a file
  replaced after it was found is caught too. A program that is not admitted
  is `Failure.unverified(path:reason:)`; a refused process is killed with
  its group before it runs or reads its input; each admission and refusal
  is recorded to the unified log. The exit is waited for only once the
  program runs: macOS answers a `waitid` for `WEXITED` alone with a
  suspended child's stop (`CLD_STOPPED`).
- This release removes public API, and every consumer pins an exact
  version: `InstalledProgram(name:variable:leading:)` and the `environment:`
  parameter of `candidates` and `executable` are gone. Every app passes
  `name` (and `identifier:`, or `team:` for a program another publisher
  signs) and says `Failure.unverified` in its own words.
- A run no longer hands the program the app's variables that begin with
  the program's own name (`PARA_`, where it keeps state and keys), `XDG_` or
  `DYLD_` (`InstalledProgram.withheld`): any process of the account can set
  them for the app with `launchctl setenv`. `run(…, withholding:)` names
  more (`NODE_`, `OPENSSL_CONF` for a Node.js runtime); what a run needs is
  set with `environment:`.
- `FleetSignature` checks a file or a child process against the fleet's (or a
  named publisher's) requirement, for an app that keeps a server running.
  The requirement names the team, not Developer ID: the fleet CLIs carry an
  Apple Development certificate of the team.
- `FleetSignatureTests` refuses a stand-in where `PATH` or the old variable
  led, a stand-in script and a renamed copy of `/bin/sh` (errSecCSReqFailed)
  where the installer places the program, kills a run of `/bin/sh` as `para`
  before it writes or reads anything, runs an installed `stado` through the
  suspended check, and refuses a running process as not untouched.

### A refused or unreachable support report names the product's own command

- `support-refused` and `support-unreachable` tell the reader to send the
  report again with `{product} support report`, and neither runtime gave
  them the product: Rust's remedy said `{product}` as written and its
  failure carried `wisent_errors.unfilled=product`, and Swift's Report a
  Problem window, `support report` and `support status` showed the
  placeholder. Both runtimes now give each cause the product's id, and the
  support tests of both check the remedy names `<product> support report`
  with nothing left unfilled.

### A stop after the program's group exited keeps the run's outcome

- `InstalledProgram`'s stop signals the program's process group with
  `killpg`. A stop that came after every member exited, but before the run
  reaped the program, met `killpg` failing, since macOS skips a zombie and
  answers ESRCH (EPERM in POSIX mode) when it signalled no member, and
  ended the run as `unfollowed`, dropping the program's real status and
  output. When `killpg` answers ESRCH or EPERM and the program itself has
  exited, its exit waiting to be reaped, the stop now leaves the run to that
  exit, which ends it with the outcome. While the program still runs (a live
  member this app may not signal answers the same), and on any other
  `killpg` failure, the run ends as `unfollowed` as before.
  `InstalledProgramTests` stops a program that has already exited on
  SIGTERM, with its exit not yet reaped, and checks the run ends signalled
  by SIGTERM.

### A consent file with an unknown level names its own size

- `file-unreadable` for a consent file whose level is not off, errors or
  usage said the file held as many bytes as its object written again, which
  differs from the file whenever it holds other spacing or key order. Both
  runtimes now name the bytes read from the file, and both damaged-consent
  tests write a spaced file with a second key and check the size named is
  the file's.

### An unreadable support answer is named, not read as empty

- Rust's support exchange read a body it could not read as empty text, so
  a connection lost mid-answer was reported as `support-answer-unreadable`
  holding no answer, or a refusal lost its reason. It is now
  `support-unreachable` naming the HTTP status that came and why the body
  could not be read, as the collector's delivery and Swift's exchange
  already report it.

### Telemetry's causes are declared in the catalogue, for Rust and Swift alike

- Telemetry's and support's causes were written by hand twice: as statics in
  `rust/src/telemetry/causes.rs`, past `catalogue/failures/` and the
  generator, and as sentence literals in Swift's `TelemetryError` and
  `SupportError`, which had drifted from Rust's (a damaged consent file
  named no byte count, an invalid collector address named no fix, a
  failed send to the collector a different remedy). They are now
  `catalogue/failures/telemetry.json`, generated into
  `rust/src/failures/telemetry.rs`, `OwnFailuresTelemetry.swift` and
  `docs/errors/telemetry.md`; `causes.rs` is gone, and Swift raises each
  through its generated `OwnFailures` cause, so both say the same sentence.
  `store-unwritable` and `file-unreadable`, which every functionality meets,
  are `wisent-errors.telemetry.store`; the support address and exchange
  causes, which `support report` and `support status` share, are
  `wisent-errors.support.exchange`; each functionality lists them in `uses`,
  and `telemetry::operations()` lists those two as well (seven, no longer
  five). `support status` now declares `store-unwritable`, which it raises
  when its reports directory cannot be listed. `RECORD`, `CONSENT`,
  `DELIVER`, `REPORT` and `STATUS` keep their names in `telemetry`; their
  `docs` and every cause's `doc` point at `docs/errors/telemetry.md`, the
  page that holds the anchors.
- `collector-failed`'s fix names `{product} support report` and an app's
  Help → Report a Problem; Swift's removal of a sent event or of the queue
  is `store-unwritable`, as in Rust. The fixes Swift's windows also show
  name both surfaces: a report's description, a refused or unreachable
  report, and a damaged consent file each name the app's Report a Problem
  window or settings beside the command. Swift's own cases meet an
  unwritable directory, a damaged consent file, an unreachable collector,
  an address that is not the collector and one that is not support
  (`TelemetryTests.swift`, `SupportTests.swift`).
- `codegen/generate.mjs` claimed CI regenerates and fails on a difference;
  no CI runs here. It now says `--check`, run by `node ci/check.mjs` (the
  `checks` gate of `.wisent-release.json`), is what keeps the copies equal.
- The generated files are written by `node codegen/generate.mjs`; the
  `checks` gate's `--check` confirms them. Nothing was built or tested here.

### A telemetry flush says what it waits on, and says when in local time

- `Telemetry::flush` sent each event with a ureq agent nothing reported, so a
  collector that accepted the connection and never answered held the flush
  (ster's detached `telemetry flush`) with no word anywhere. Each send is
  now a stado-wait wait (`telemetry` feature: `stado-wait` 0.2.0 without its
  clients): in the register `stado waits` lists, said on stderr when it
  stands, measured. It ends on evidence (the collector answers, refuses or
  closes, or the process is ended), never after a guessed time
  (`tests/telemetry/delivery.rs::a_collector_that_closes_without_answering_ends_the_flush_and_keeps_the_events`).
  An answer whose body could not be read was taken as an empty body; it is
  now `collector-unreachable` naming the status and the read's error.
- `delivery.json`'s `at`, which `telemetry status` and the Settings window
  show a person, was UTC (`…Z`). It is now this host's local time with its
  offset (`2026-11-16T14:03:07.120+01:00`), in Rust and in Swift
  (`tests/telemetry/delivery.rs::the_last_delivery_says_when_in_local_time_with_its_offset`).
  An event's `occurredAt` and the consent and installation records stay
  UTC: programs read them, people do not.
- `Cargo.lock` locks stado-wait and chrono (`kompilator lock --manifest-path
  Cargo.toml`). Written and read; nothing was built or run.

### `WisentProgram` stops the whole program and ends on its exit

- `InstalledProgram.run` started the program with `Process`, sent only it
  SIGTERM on cancellation with no way to insist, and ended only once both
  pipes closed, so a process the CLI left running with its output kept the
  run open after the CLI exited. The program now runs in a process group of
  its own (`posix_spawn`, `POSIX_SPAWN_SETPGROUP`): cancelling the task sends
  the group SIGTERM, and a further `InstalledProgram.Stop.request()` sends it
  SIGKILL, on that request and never after a guessed wait. The run ends on
  the program's exit with everything its streams hold then;
  `Outcome.heldOpen` names a stream a process it started still held, so
  what that process writes later is not dropped unsaid. A run whose exit
  cannot be waited for (an app that ignores SIGCHLD reaps it first) is the
  new `Failure.unfollowed(path:step:reason:)`, which a product says in its
  own words beside the other two (`tests/program/InstalledProgramTests.swift`:
  `testCancellingTheCallerStopsEveryProcessOfTheProgramsGroup`,
  `testASecondRequestKillsAProgramThatIgnoresTheFirst`,
  `testAStopRequestedBeforeTheRunRefusesIt`,
  `testAProcessTheProgramLeftHoldingItsOutputDoesNotHoldTheRun`,
  `testAProgramThatCannotStartIsRefusedNamingWhy`,
  `testAProgramSomethingElseReapedIsRefusedNamingTheWait`). No consumer
  switches over `InstalledProgram.Failure`; each catches its cases by name,
  so the new case breaks no build. Until a product catches
  `Failure.unfollowed` in its own words, it reaches the person as the case
  itself, naming the path, the step and the reason. Written and read;
  nothing was built or run.
- `run` takes the program's `input`, written to its standard input while
  both output streams are read, then its end; `Outcome.inputDelivered` is
  false when the program closed its input (EPIPE, never SIGPIPE here:
  `F_SETNOSIGPIPE`) or exited with some still unwritten. It takes an
  `environment` set over the app's; a name that is empty or holds `=` is
  refused before the program starts
  (`testTheInputIsTheProgramsStandardInputThenItsEnd`,
  `testAProgramThatClosesItsInputEarlyIsToldApartAndSignalsNothingHere`,
  `testTheEnvironmentIsSetOverTheAppsOwn`,
  `testAnEnvironmentNameHoldingAnEqualsSignIsRefusedBeforeTheProgramStarts`).

### SwiftPM pins a tag, and the version files stay at what consumers declare

- `docs/maintaining/pinning.md` said every consumer pins a commit, while
  SwiftPM consumers pin a tag, as SwiftPM requires of a package depended on
  by version; it now says so. It also says why `package.json`,
  `rust/Cargo.toml` and `python/pyproject.toml` stay `1.0.0` below the tag
  line: eight Cargo consumers declare `version = "1.0.0"` against the git
  source, and cargo refuses a crate version that does not meet it.
- `.wisent-release.json` declares test gates: `node ci/check.mjs` (the
  catalogue checks and every node test), each Rust test target that needs
  no live collector, three delivery tests that need none, and `swift test`
  for `WisentErrorsTests` and `WisentProgramTests`. Its reason says how each
  ecosystem pins and that the version tags exist.

### The JavaScript runtime and the commands keep their parts apart

- `js/` held twelve files. The generated catalogue (`codes.mjs`,
  `declaration.mjs`, `failures.mjs`) and the `codes.d.ts` beside it are now
  in `js/catalogue/`, which `codegen/generate.mjs` writes. The declaration
  checks (`operation.mjs`, `refusal.mjs`, `template.mjs`, `warning.mjs`) are
  now in `js/declared/`. The `.` and `./codes` exports name the same modules
  as before, so an importer of `@wisent/errors` or `@wisent/errors/codes`
  changes nothing. A copy that imported `js/<file>.mjs` by its path names the
  new folder.
- `ci/` held nine files. The four the commands share (`refuse.mjs`,
  `input.mjs`, `arguments.mjs`, `tests-held.mjs`) are now in `ci/support/`.
  The commands a consuming repository runs (`ci/error-standard.mjs`,
  `ci/warning-standard.mjs`, `ci/no-handrolled-envelope.mjs`,
  `ci/find-implementations.mjs`, `ci/check.mjs`) keep their paths.
- `rust/src/operation/` held six files. `cause.rs` and `declared.rs` are now
  in `rust/src/operation/causes/`; `wisent_errors::operation::{Cause,
  Declared}` are where they were. Written and read; nothing was built or run.

### `WisentProgram` says a character two reads split whole

- `InstalledProgram.run` decoded each pipe read on its own, so a character
  whose UTF-8 bytes arrived in two reads (`ł`, `ó`, `–`) became two U+FFFD
  in `Outcome.stdout`/`stderr`, in what `onOutput` was handed, and in the
  JSON a Mac app parses from its CLI. The bytes of a character a read cuts
  short now wait for the read that completes it, and what is left at end of
  file is decoded as it is (`tests/program/InstalledProgramTests.swift`).
  Written and read; nothing was built or run.

### `causeOf` never throws, and says no empty sentence

- `causeOf` said an object as `JSON.stringify` of it, which throws on an
  object that holds itself or a bigint, so the catch that called it failed
  with a TypeError of its own instead of saying why. Such a value is now
  said with `"[Circular]"` and the bigint's digits. An empty message no
  longer opens the line with `": "`, a cause that is no Error is said once
  like an Error's, and an Error whose chain says nothing is its name
  (`tests/cause/of.mjs`). Written and read; nothing was built or run.

### `WisentProgram` finds the program the release installer placed

- `InstalledProgram.candidates` looks in `~/.local/bin/<name>` after `PATH`
  and before `~/.stado/bin/<name>`. A product's release installer
  (`stado://releases/<product>/<version>/<platform>/install.sh`) places its
  programs in `~/.local/bin` and removes the copy the retired `stado product
  install` left in `~/.stado/bin`, while an app opened from Finder or the
  Dock runs with launchd's `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), so
  every Mac app driving its CLI through `WisentProgram` said the program was
  not installed right after the installer placed it
  (`tests/program/InstalledProgramTests.swift`). A product sees it when it
  moves its pin. Written and read; nothing was built or run.

### A warning entry's heading spells its anchor

- `warnings_markdown` (Rust `output/warning.rs`), `warningsMarkdown()` (Swift
  `Warning.swift`, `js/warning.mjs`) head each warning `` `op.id` warning
  `warning-id` ``, whose words spell the anchor above it
  (`op-id-warning-warning-id`): the heading was `` `op.id.warning-id` ``,
  which spells none, so a site that gives a heading the id its words spell
  (oko.wisent.com) held no element for any warning link. A product sees it
  when it moves its pin and writes its warnings page again. Written and read;
  nothing was built or run.

### Telemetry status says an installation or delivery file it cannot read

- `status()` (Rust `telemetry/asked/mod.rs`, Swift `Telemetry/Status.swift`)
  read `installation.json` and `delivery.json` through `.ok()` / `try?`, so a
  file that was there and could not be read showed `installation: null` and
  `last_delivery: null`, as if nothing had been written. Each is now
  `{"unreadable": …}` with the reader's sentence, as `level` and `queued`
  already were (`docs/telemetry.md`, Status). Written and read; nothing was
  built or run.

### `WisentProgram`: the installed CLI a Mac app runs

- `InstalledProgram` (`swift/Sources/WisentProgram`, macOS only): the places
  a product's CLI is looked for (its variable, `PATH`, `~/.stado/bin`), the
  first executable one or `Failure.missing(searched:)`, and one run of it
  with both streams read whole and SIGTERM on cancellation. para-, prawo-,
  rachuba-, trends- and zdrowie-desktop each kept the same 195 lines as
  `<Product>Program.swift`; they declare one `InstalledProgram` instead
  (`tests/program/InstalledProgramTests.swift`). Written and read; nothing
  was built or run.

### `causeOf`: the one line a caught value says about why it failed

- `causeOf(error)` (`js/cause.mjs`): an Error's message followed by each
  `cause` under it, said once, or a value that is no Error as text, an
  object as its JSON. Twenty-odd Wisent programs (competitors-cli,
  googleads-cli, metaads-cli, seo-cli, deep-analytics, entitlements-rotator,
  people-rotator, ssh-auth-router, las, kronika, weles-web, wisent-trade, …)
  each kept the same function as a file of their own; the products that
  depend on `@wisent/errors` import it from here (`tests/cause/of.mjs`).
  Written and read; nothing was built or run.

### `Declared`: the raised cause products kept a copy of

- Kupiec, most-core, probierz, skryba, skrzynka, spis, ster, stado and
  stado-product each kept a type holding a `&'static Cause` and the values
  its sentences are filled with, displayed as its refusal, and found beneath
  wrapping errors by walking the chain. `wisent_errors::Declared`
  (`rust/src/operation/declared.rs`) is that type once, the Rust form of the
  JS `DeclaredError`: `new(cause, values)`, `values()`, `sentence()`,
  `fix()`, `exit_code(failure_exit)`, `code(operations)` (the full id) and
  `in_chain(error)`; `Display` is `Cause::refusal`. A product keeps only what
  is its own (an HTTP status, an operation, a context) beside it
  (`tests/declared/raise.rs`). Written and read; nothing was built or run.

### Turning Swift telemetry off drops the queue, or says it could not

- `setLevel(.off)` promises that turning telemetry off drops what waits, but
  removed the queue with `try?`, so a refused removal kept the events, which
  went out if telemetry was turned on again. A sent event's removal was
  dropped the same way, so the next flush sent it again with nothing said.
  Both now remove through `remove(_:what:left:)` (`Telemetry/Files.swift`):
  a missing file is what removal wanted, any other failure throws
  `TelemetryError.unwritable` from `setLevel`, and stops `flush` naming the
  event, as the Rust port already did (`telemetry/mod.rs`,
  `delivery/deliver.rs`). Written and read; nothing was built or run.

### Telemetry's own causes pass the template rules they enforce

- Five telemetry causes (`store-unwritable`, `file-unreadable`,
  `collector-unreachable`, `flush-unstarted`, `support-unreachable`) put the
  raw `{error}` in their cause, which `template_problems` refuses outside
  `observed`, and `collector-answer-unreadable` wrote the collector's
  `{"ok": true}` as literal braces, which it reads as a malformed
  placeholder; `tests/telemetry/delivery.rs::every_declared_cause_has_its_test_here`
  checks `operation.problems()` over all of them. The causes name the
  reason `{why}` and the accepted answer `{accepted}`, passed at every raise
  site in `rust/src/telemetry`, so every sentence reads as before. Written
  and read; nothing was built or run.

### `Error.explained` says an encoding failure

- An `EncodingError` bridged to "The data couldn't be written because it isn't in
  the correct format. (NSCocoaErrorDomain 4866)", without the value refused or the
  field it stood at, so apps dumped it with `String(describing:)` instead. It is
  said as `<type> <value> cannot be encoded at <coding path>: <encoder's reason>`
  (`swift test --filter ExplainedTests`,
  `testAnEncodingFailureNamesTheValueThePathAndTheEncodersReason`).

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
