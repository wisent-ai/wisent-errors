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
  the `Failure` a user would meet, with its detail and remedy.
- `Probe::Skipped("why")` says why it is not tried: it changes the user's
  data, or it needs input only its own command carries.

`diagnosis::problems(operations, checks)` names a functionality with an entry
point and no check, one checked twice, and a check of a functionality the
catalogue does not declare. The product's catalogue test asserts it is empty,
so a functionality is in the diagnosis the moment it is declared, and the test
fails until it is tried or its skip is explained.

## Test

`kompilator test --manifest-path rust/Cargo.toml --features diagnosis --test diagnosis` runs probes that read a
file that is there and one that is not, in a directory of the run's own under
`.build/diagnosis/`, and holds a set of checks to a catalogue with a
functionality left out, one checked twice and one undeclared.
