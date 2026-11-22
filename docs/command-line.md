# The `wisent-errors` command line

The crate's own program (`rust/src/bin/wisent-errors/`, built with the
`cli-output`, `telemetry` and `diagnosis` features). It carries the telemetry
and support commands every product CLI carries from this crate
([telemetry.md](telemetry.md), [support.md](support.md)), run for the product
a product file names, so a product written in any language reports through
it; a `doctor` over those functionalities ([diagnosis.md](diagnosis.md)); and
the warnings it declares.

```
wisent-errors [--product <file>] [--text] <command> [operands] [options]
```

```sh
cargo install --git https://github.com/wisent-ai/wisent-errors wisent-errors \
  --features cli-output,telemetry,diagnosis
```

A result is printed on standard output as pretty JSON, or with `--text` as one
`path: value` line per field (`cli_output::output`). A refusal prints nothing
on standard output and says three lines on standard error, as every command of
this package does:

```
Error: <what failed>: <why>; observed: <the state it found>
fix: <what to do>
cause: <operation>.<cause id>; <its entry under docs/errors/>
```

and the process exits with the status the cause declares: 2 for a command
line refused for its own form (a usage refusal), 69 for a failure worth
running again unchanged (`infra_down`, `timeout`, `rate_limit`), 1 otherwise.
The refusals of the command line itself are the causes of
`wisent_errors.command.arguments` and `wisent_errors.command.product`
([errors/command.md](errors/command.md)); those of what a command does are
the causes of the functionality it runs ([errors/telemetry.md](errors/telemetry.md),
[errors/cli-output.md](errors/cli-output.md), [errors/envelope.md](errors/envelope.md)).

## The product file

Every command that speaks for a product names its file with `--product`: a
JSON object with

| key | what it is |
|---|---|
| `id` | the product's id, the name of its own command (`example-product`), lowercase words joined by `-`; its telemetry is kept under it |
| `app_id` | the app id the collector declares for this surface of the product (`example-product-cli`) |
| `version` | the version this copy reports |
| `flush` | optional: the words of the command that sends the queue, its program first (`["example-product", "telemetry", "flush"]`); started in the background after `telemetry failure` and `telemetry command`, never waited for |

A file that is absent or not JSON is refused as `wisent_errors.cli_output.read_json`
refuses any JSON input; a field that is not what it should be is
`product-field-invalid`, naming the field, what it holds and an example.

## Where it keeps its files, and what it talks to

Telemetry lives in `WISENT_TELEMETRY_HOME`, else
`$XDG_STATE_HOME/<id>/telemetry`, else `~/.local/state/<id>/telemetry`
([telemetry.md](telemetry.md) lists every file). Events go to the public
collector unless `WISENT_TELEMETRY_COLLECTOR_URL` names another, reports to
Wisent's support unless `WISENT_SUPPORT_URL` names another, and
`DO_NOT_TRACK=1` turns every level off. Nothing else is read or written.

## Commands

| command | what it does | prints |
|---|---|---|
| `telemetry status` | reads the store | the product, its level, `DO_NOT_TRACK`, the collector and what named it, the installation id, how many events wait, the last delivery, the directory; a file it cannot read is `{"unreadable": <sentence>}` |
| `telemetry level <off\|errors\|usage> [--yes]` | keeps the user's answer | the status |
| `telemetry on` | the `errors` level | the status |
| `telemetry off [--yes]` | the `off` level, which removes the waiting events: while any wait it warns (below) and does nothing until `--yes` | the status |
| `telemetry failure <failure-point> <code> [--detail <text>] [--remedy <text>] [--impact <text>] [--cause-id <id>]` | queues the failure the product met, under `errors`, and counts a repeat in a row | the status |
| `telemetry command <name> <exit-status> <duration-ms>` | queues a command the product ran, under `usage`, and counts a usage loop | the status |
| `telemetry help <command>` | counts help asked after a failure, under `usage` | the status |
| `telemetry show` | reads the queue | every waiting event, oldest first, as it will be sent |
| `telemetry events` | needs no product | every event the reporter can send, its consent and its properties |
| `telemetry export <file>` | writes the queue to `<file>`; the events stay queued | how many, and the file |
| `telemetry flush` | sends the queue to the collector | `sent`, `remaining`, `stopped`, `skipped`; when it stopped, the refusal follows on stderr |
| `support report --description <text> [--subject <text>] [--email <address>] [--with-failure]` | files a report with support and keeps its key | support's id, its status, the address, where the key is kept |
| `support status` | reads every filed report back from support | each report's state and replies |
| `doctor [--json]` | tries every functionality now, sends nothing | one line per functionality, `ok`, `failed` with its fix, or `skipped` with why; exits 1 when one failed |
| `warnings list` | needs no product | every functionality that warns, each warning linked to its entry below |
| `warnings page` | needs no product | the section below, as this page holds it |
| `errors list` | needs no product | every functionality the command runs and every cause it declares, as `Operation::to_json` lists them |
| `errors page` | needs no product | every functionality the command runs as its failure page section (`Operation::markdown`), each cause under the class its refusal prints: `usage` for a usage cause, whatever code it carries |
| `doctor check <errors-list.json> <doctor.json>` | needs no product; holds the findings a product's `doctor --json` printed to the functionalities its `errors list --json` declares (`diagnosis::problems`); refuses a functionality with an entry point and no check, one checked twice, and a check of one the catalogue does not declare (`wisent_errors.command.check.doctor-incomplete`) | how many functionalities, how many with an entry point, how many findings |
| `warnings check <warnings-list.json>` | needs no product; holds each warning a product's `warnings list` printed to the declaration rules (`Operation::warning_problems`, the hazard read with `Hazard::parse`): a warning declared twice, an empty field, a malformed test, an unknown hazard (`wisent_errors.command.check.warnings-invalid`) | how many functionalities, how many warnings |

A failure of telemetry itself while `telemetry failure`, `command` or `help`
runs (a store it cannot write, a background flush that cannot start) is said
once on stderr, starting with `wisent-errors: telemetry:`, and the command
still prints the status and exits 0, as in every product.

## Warnings

## `wisent-errors.telemetry.consent`

keep the level of telemetry the user chose

Started through: `<product> telemetry on|off`, `Telemetry::ask`, `Telemetry::set_level`. 1 declared warning(s).

<a id="wisent-errors-telemetry-consent-warning-queue-dropped"></a>

### `wisent-errors.telemetry.consent` warning `queue-dropped`

- **Kind:** `irreversible`: removes or rewrites something nothing in the product restores afterwards
- **What it does:** turning telemetry off removes the {queued} event(s) waiting in {queue}
- **What cannot be had back:** nothing sends them afterwards and nothing brings them back, so the failures they record never reach the maintainers of {product}
- **Before confirming:** keep them with `{product} telemetry export <file>`, which writes them as they would have been sent, or send them first with `{product} telemetry flush`
- **To go ahead:** rerun with --yes
- **Test:** `tests/telemetry/consent.rs::telemetry_level_keeps_the_answer_and_asks_before_dropping_waiting_events`

An unconfirmed `telemetry off` prints nothing on standard output, says on
standard error

```
Warning: <what it does>; <what cannot be had back>; nothing was done. Before confirming: <…>. To go ahead: rerun with --yes
warning: wisent-errors.telemetry.consent.queue-dropped; https://github.com/wisent-ai/wisent-errors/blob/main/docs/command-line.md#wisent-errors-telemetry-consent-warning-queue-dropped
```

and exits 2.

## Tests

`tests/telemetry/`, `tests/diagnosis/main.rs`, `tests/warnings/declaration.rs` and `tests/errors/page.rs`
run this program as a process, with its environment cleared and a home of
each case's own:

```sh
kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test errors
kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test telemetry
kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test diagnosis
kompilator test --manifest-path rust/Cargo.toml --features cli-output,telemetry,diagnosis --test warnings
```
