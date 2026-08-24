# Configuration

The package reads almost nothing from its environment, on purpose: a
vocabulary that behaves differently per machine is not a vocabulary. The
complete list — two environment variables and one file, all read by the
Swift `WisentFailureReporter` and by nothing else in the repository. The
Rust, Python, and JavaScript runtimes read no environment at all;
everything a product decides (trim width, chosen exit code, failure
points) is a function argument, not configuration.

## `PROBIERZ_INTAKE_URL`

The origin of the Probierz intake the reporter POSTs to — origin only,
no path: `/v1/failures` is appended. Read from the process environment at
**call time**, not at load time, so a launcher that sets it late still
wins. Only used when `PROBIERZ_INTAKE_TOKEN` is also set and non-empty.

```
PROBIERZ_INTAKE_URL=http://127.0.0.1:19790
```

## `PROBIERZ_INTAKE_TOKEN`

The bearer token sent as `Authorization: Bearer <token>` with each report.
Read at call time, paired with `PROBIERZ_INTAKE_URL`: with either variable
absent or empty, the pair is ignored and the fallback below is tried.

## `~/.probierz/intake-token`

The loopback fallback. With the environment pair unavailable, the reporter
tries `http://127.0.0.1:9790` with the token read from this file — the
file the intake itself creates (0600) on first run, and exactly the
configuration a Finder-launched app inherits nothing of. The content is
trimmed; an empty or unreadable file (a sandboxed app may be refused the
read) is the same as an absent one.

## With neither

`report` is a no-op. Misconfiguration ends the same way as a refusal or an
unreachable intake: the report is dropped and the app behaves exactly as
before — reporting must never fail the caller
([concepts/report](concepts/report.md)).

## Resolution order, exactly

1. `PROBIERZ_INTAKE_URL` + `PROBIERZ_INTAKE_TOKEN`, both non-empty → use
   them.
2. Otherwise `~/.probierz/intake-token` readable and non-empty → loopback
   `http://127.0.0.1:9790` with that token.
3. Otherwise → no-op.

There is no partial mix: an environment URL without a token (or the
reverse) falls through to step 2, it does not borrow the file's token for
the environment's URL.

## What is deliberately not configuration

- **Trim width.** `trimDetail(text, limit)` takes the width as an
  argument; `DETAIL_LIMIT` (2000) is the package's own bound, a constant,
  not a knob ([boundary](boundary.md)).
- **Exit codes.** `exitCode(code, chosen)` takes the caller's chosen code
  as an argument; `RETRY_EXIT` (69) comes from the catalogue.
- **The vocabulary and every derived field.** Catalogue, generated,
  conformance-checked ([catalogue](catalogue.md)); nothing about them can
  be configured per deployment, which is the point of the package.
- **Transport for Rust, Python, JS.** Those runtimes return strings; each
  product's emitter and its configuration stay in the product
  ([boundary](boundary.md)).
