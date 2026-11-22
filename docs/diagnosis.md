# Diagnosis: `<product> doctor`

`<product> doctor` goes through every functionality the product's catalogue
declares and tries it now, on this machine: the installation is complete, the
directories it writes can be written, the services it calls answer. For each
one it says that it works and what it saw, or what failed and how to fix it,
or that it was not tried and why. A person whose product misbehaves runs it
before writing to support; support asks for its output first.

```text
ok      ster.telemetry: ~/.local/state/ster/telemetry can be written; the collector https://telemetry.wisent.com/api/analytics/mobile/collect answers
failed  ster.support: reaching https://support.wisent.com/v1/public/reports: connection refused; fix: check the network, or report the problem from another machine
skipped ster.workspace.remove: it deletes a workspace the user chose
```

`<product> doctor --json` prints the same findings as an array of
`{"operation", "state": "works"|"fails"|"skipped", ...}`: a failing one
carries its `failure_point`, `error_code`, `detail` and `remedy`, a working
one what it `observed`, a skipped one `why`. The command exits 0 when nothing
failed and 1 when a functionality failed.

## The list comes from the catalogue

A product gives one `diagnosis::Check` (feature `diagnosis`) per functionality
of its catalogue that has an entry point:

- `Probe::Run(fn)` tries it: `Ok` says what was observed working, `Err` is
  the `Failure` a user would meet, with its detail and remedy. A `Failure`
  without either is not printed with words standing in for them: the
  diagnosis refuses it as
  `wisent_errors.cli_output.diagnose.probe-failure-unexplained`
  ([errors/cli-output.md](errors/cli-output.md)), naming the functionality,
  what the envelope lacks, its point and its code, so the fix is to raise
  the probe's failure from a declared cause.
- `Probe::Skipped("why")` says why it is not tried: it changes the user's
  data, or it needs input only its own command carries.

`diagnosis::problems(operations, checks)` names a functionality with an entry
point and no check, one checked twice, and a check of a functionality the
catalogue does not declare. The product's catalogue test asserts it is empty,
so a functionality is in the diagnosis the moment it is declared, and the test
fails until it is tried or its skip is explained. A product's CI that is not
written in Rust runs the same rule as a command:
`wisent-errors doctor check <errors-list.json> <doctor.json>` holds what
`<product> doctor --json` printed to what `<product> errors list --json`
declares and refuses each problem as
`wisent_errors.command.check.doctor-incomplete`
([command-line.md](command-line.md)).

## Test

`kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test diagnosis`
runs `wisent-errors --product <file> doctor` and `doctor --json`
([command-line.md](command-line.md)) as a process, with its environment
cleared and a home of the case's own under `CARGO_TARGET_TMPDIR`: everything
working, a damaged consent file and a collector and a support address it
refuses, and a telemetry directory below a file, each finding compared whole
and the store read back after each run. The diagnosis's refusal of a probe
that fails without saying why (`probe-failure-unexplained`) is listed in
tests/untested-causes.json: every probe of the command raises a declared
cause, so only a product's own probe code can meet it. The same target runs
`wisent-errors doctor check` over the command's own `errors list --json` and
`doctor --json` (`doctor_check_holds_the_findings_to_the_errors_list`): the
two agreeing, a missing operand, an absent file, a document of the wrong
shape, and findings that miss a functionality, try one twice and try one the
catalogue does not declare, each refusal compared whole and both files read
back unchanged.
