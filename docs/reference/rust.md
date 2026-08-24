# Rust API reference

Crate `wisent-errors`, in `rust/`, named by the root Cargo workspace so a
git dependency resolves. Edition 2021, zero dependencies — no serde;
serialization is hand-rolled in the schema's key order. All refusal
sentences below are the exact `Display` strings.

## Types

### `enum Code`

`Config`, `Auth`, `NotFound`, `RateLimit`, `Timeout`, `InfraDown`,
`Unknown`. `Copy`, `Ord`, `Hash`, `Display` (prints `as_str()`). An
off-catalogue code is unrepresentable — this is the strictest of the four
runtimes: even the salvage builder takes a `Code`.

| item | contract |
|---|---|
| `Code::RETRY_EXIT: i32` | `69` (`EX_UNAVAILABLE`) |
| `Code::ALL: &[Code]` | the seven, catalogue order |
| `as_str() → &'static str` | the wire string (`"not_found"`, …) |
| `parse(text) → Option<Code>` | the honest wire-boundary primitive: `None` for anything off-catalogue |
| `or_fallback(text) → Code` | `parse` or `Code::Unknown`; never fails |
| `operator_summary() → &'static str` | the catalogue's per-code sentence |
| `retryable() → bool`, `outage() → bool`, `severity() → Severity` | derived, from the generated table |
| `http_status() → u16` | the edge status |
| `exit_code(chosen: i32) → i32` | `RETRY_EXIT` when retryable, else `chosen` |
| `from_upstream_status(status: u16) → Code` | exact matches, then the inclusive 500–599 range → `InfraDown`, else `Unknown` |

### `enum Severity`

`Warning`, `Error`, `Critical` — ordered (`PartialOrd, Ord`), so
`severity >= Severity::Error` works; `as_str()` and `Display`.

### `struct Failure`

All fields public: `failure_point: String`, `code: Code`, `service:
String`, `impact: Option<String>`, `detail: Option<String>`, `cause:
Option<Box<Failure>>`, `context: Context`. `Clone`, `Debug`, `PartialEq`,
`Eq`; implements `Display` (prints `render()`) and `std::error::Error`, so
a `?`-propagated failure prints the full rendered line.

### `type Context = BTreeMap<String, String>`

A `BTreeMap` so context keys serialize in sorted order and the bytes match
the other runtimes.

### `enum Invalid`

Why an envelope could not be built. `Display`:

| variant | exact sentence |
|---|---|
| `Invalid::FailurePoint(point)` | `failure_point "Not A Point" is not a dotted lowercase path` (`{point:?}`) |
| `Invalid::Empty("service")` | `service must not be empty` |

Implements `std::error::Error`.

## Building

### `Failure::new(failure_point, code, service) → Result<Failure, Invalid>`

The strict builder. Trims `failure_point` and `service`; refuses a point
that fails the grammar (lowercase dotted path — the validator additionally
refuses a trailing `-`/`_` and doubled separators inside a segment) and an
empty service. The code cannot be wrong: it is a `Code`.

### `Failure::or_fallback(failure_point, code, service) → Failure`

The salvage builder; never fails. An empty point becomes `unknown` with
`wisent_errors.failure_point: absent` in `context`; a malformed one is kept
verbatim with `wisent_errors.failure_point: malformed`; an empty service
becomes `unknown` with `wisent_errors.service: absent`. There is no
off-catalogue-code note — the type system refuses the bad code before a
note could be recorded, which is why the golden case for that path has no
Rust side.

### Builder methods (consume and return `Self`)

| method | contract |
|---|---|
| `impact(impl Into<String>)` | trimmed; empty becomes `None` |
| `detail(impl Into<String>)` | trimmed to `DETAIL_LIMIT` (2000, counted in `chars`); all-whitespace becomes `None` |
| `caused_by(Failure)` | boxes the failure underneath this one |
| `with_context(key, value)` | inserts one context pair |

### Accessors

`severity()`, `retryable()`, `outage()` — delegated to `self.code`.

## Rendering

### `to_json() → String`

The envelope in the schema's key order: `failure_point`, `error_code`,
`service`, `impact`, `severity`, `retryable`, `outage`, `detail`, then
`cause` (recursive) and `context` when present. Absent optionals are
written as `null`, never dropped. Escaping is minimal JSON: `"`, `\`,
`\n`, `\r`, `\t`, and `\u00XX` for other control characters — identical
across the four runtimes, which the conformance harness checks.

### `render() → String`

One line: `<operator_summary> — <whose><retry> <to_json()>` with the same
derived wording as every runtime; the separator is an em dash (U+2014).

### `chain() → Vec<String>`

One row per cause-chain layer, outermost first:
`<failure_point> [<code>] <detail or ->`.

## Trims

### `trim_detail(text: &str, limit: usize) → String`

Trims both ends, cuts hard at `limit` — counted in `chars`, not bytes; a
multibyte detail keeps `limit` characters. No default limit: the width is
the caller's argument, with `DETAIL_LIMIT` (`usize`, 2000) as the
package's own bound.

### `trim_detail_at_word_edge(text: &str, limit: usize, slack: usize) → String`

The same, cut back to the last space when one falls within `slack`
characters of the bound; right-trimmed. Opt-in, because it changes emitted
bytes. The edge is found in characters: the first version compared a byte
offset from `rfind` against a character limit and discarded two thirds of
a non-ASCII detail — provider text in this fleet is not ASCII.

## Executed

Every sentence above is exercised by
[examples/rust-consumer.sh](../examples/rust-consumer.sh) (a scaffolded
consumer, compiled and run, exiting 69 on the retryable path); its
captured output is in [integrate/rust](../integrate/rust.md).
