# Severity

Severity is how loud a failure is: `warning`, `error`, or `critical` —
exactly three values, declared once in the catalogue's `severities` array and
derived from the [code](code.md), never chosen at a call site. The schema's
own description of the field is one sentence: "Derived from the code, never
chosen at the call site."

## The mapping

| code | severity |
|---|---|
| `config` | critical |
| `auth` | warning |
| `not_found` | warning |
| `rate_limit` | warning |
| `timeout` | error |
| `infra_down` | critical |
| `unknown` | error |

The shape of the mapping is legible: the two codes that mean "our deployment
is broken and will stay broken until someone acts" (`config`, `infra_down`)
are `critical`; the refusals that are about one request or one credential
(`auth`, `not_found`, `rate_limit`) are `warning`; the two where the truth is
unknown (`timeout` — no verdict arrived; `unknown` — unattributed) are
`error`.

## Shape per runtime

- **Rust** — `enum Severity { Warning, Error, Critical }`, ordered
  (`PartialOrd, Ord`), with `as_str()` and `Display`. Read via
  `code.severity()` or `failure.severity()`.
- **Swift** — `enum Severity: String, CaseIterable` with cases `warning`,
  `error`, `critical`. Read via `code.severity` or `failure.severity`.
- **JS** — `severity(code)` returns the string; `SEVERITIES` is the frozen
  three-element array.
- **Python** — `severity(code)`; `SEVERITIES` names the three in order
  (annotated `tuple[str, ...]`, generated as a list).

## Invariants

- **Never an argument.** No builder in any runtime accepts a severity. A
  call site that wants a different loudness wants a different code — that is
  the point: five of six hand-kept copies of the fleet's table drifted in the
  derived fields while the vocabulary stayed intact, so the derived fields
  are exactly what must not be writable ([boundary](../boundary.md)).
- **Stated twice, checked once.** The catalogue and the schema both name the
  three severities; `ci/check.mjs` fails if they disagree (`schema and
  catalogue name the same severities`).
- **Checked in every golden envelope.** `ci/check.mjs` re-derives `severity`
  for each case in `tests/conformance/cases.tsv`; a golden envelope whose
  severity disagrees with the catalogue fails the gate with
  `<case>.severity is <x>, catalogue says <y>`.

## What a wrong severity looks like

Editing one runtime's generated severity (rate_limit `warning` → `error`) and
running the gate produces — captured from a scratch copy of this repository:

```
FAIL  throttled
  expected  {..."error_code":"rate_limit",..."severity":"warning",...}
  js        {..."error_code":"rate_limit",..."severity":"error",...}
```

The full run is in [runbook](../runbook.md).

## Not to be confused with

- **Retryability.** `error` does not mean "retry" and `warning` does not
  mean "ignore": `rate_limit` is a `warning` and retryable, `unknown` is an
  `error` and not. The retry decision is its own derived field
  ([retryability](retryability.md)).
- **The outage flag.** Severity says how loud; [outage](outage.md) says
  whose fault.
