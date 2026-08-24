# Python API reference

Package `wisent-errors`, import name `wisent_errors`, under `python/`
(`pyproject.toml` there; hence `#subdirectory=python` in the pip spec).
Python ≥ 3.9, zero dependencies. Two modules: `wisent_errors` (builders,
render, chain, trims, plus every catalogue function re-exported) and
`wisent_errors.codes` (the generated catalogue module alone). All refusal
sentences below are the exact strings raised by the code.

## Builders

### `failure(*, failure_point, code, service, impact=None, detail=None, cause=None, context=None) → dict`

All arguments are keyword-only. Builds an envelope as a plain `dict` with
`severity`, `retryable`, `outage` filled from the catalogue. Raises
`TypeError` on anything malformed:

| condition | exact sentence |
|---|---|
| `failure_point` not a non-empty `str` | `failure_point must be a non-empty string` |
| `failure_point` fails the grammar | `failure_point 'Not A Point' is not a dotted lowercase path` (`{point!r}`) |
| `code` not in the catalogue | `code 'panic' is not in the catalogue; one of config, auth, not_found, rate_limit, timeout, infra_down, unknown` (`{code!r}`) |
| `service` not a non-empty `str` | `service must be a non-empty string` |
| `detail` provided but not a non-empty `str` | `detail must be a non-empty string` |

`failure_point` and `service` are stripped. `impact` accepts any value: it
is coerced through `str()` and stripped, empty becomes `None`. `detail`
omitted or `None` serializes as `None`; provided, it must be a non-empty
`str` and is trimmed to `DETAIL_LIMIT` (2000). `cause` must be a `Mapping`
and is shallow-copied with `dict(cause)` — unlike JS, a `FailureError` is
*not* unwrapped: pass `error.envelope`. `context` is shallow-copied and
omitted when empty or `None`.

### `failure_or_fallback(**fields) → dict`

The same, but it never raises. Coercions, each recorded in `context`:

| violation | result | context note |
|---|---|---|
| `failure_point` absent/empty | `"unknown"` | `wisent_errors.failure_point: "absent"` |
| `failure_point` malformed | kept verbatim | `wisent_errors.failure_point: "malformed"` |
| `code` is `None` | `"unknown"` | `wisent_errors.error_code: "absent"` |
| `code` not a `str` in the catalogue | `"unknown"` | `wisent_errors.error_code: "off-catalogue: <code>"` |
| `service` absent/empty | `"unknown"` | `wisent_errors.service: "absent"` |

Every optional is coerced through `str()` and stripped; `detail` is trimmed
to `DETAIL_LIMIT`. Caller-provided `context` merges under the notes (notes
win on collision).

### `raise_failure(**fields) → None`

`raise FailureError(failure(**fields))`.

### `class FailureError(Exception)`

`envelope` carries a copy of the data (`dict(envelope)`); the exception
message is `<failure_point>: <detail or operator_summary(error_code)>` —
`or`, so an empty or absent detail falls back to the catalogue sentence.

## Rendering

### `render(envelope) → str`

One line: `<operator_summary> — <whose><retry> <JSON>` where `<whose>` is
`our failure` / `the request or its credentials` (from `outage`) and
`<retry>` is `; retry later` / `; retrying will not help` (from
`retryable`). The JSON half is
`json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)`, so it is
byte-identical to the other runtimes; the separator is an em dash (U+2014).

### `chain(envelope) → list`

One row per cause-chain layer, outermost first:
`<failure_point> [<error_code>] <detail or '-'>` — `or`, so an empty detail
renders as `-` too.

## Trims

### `trim_detail(text, limit=DETAIL_LIMIT) → str`

Coerces (`str(text)`, `None` becomes `""`), strips both ends, cuts hard at
`limit`. The width is an argument because it is a product decision; the
rule is the shared part.

### `trim_detail_at_word_edge(text, limit=DETAIL_LIMIT, slack=24) → str`

The same, cut back to the last space when one falls within `slack`
characters of the bound; the result is right-stripped. Opt-in, because it
changes emitted bytes. The `edge > 0` guard matters: `rfind` returns -1
when there is no space at all, and for any limit under `slack` a bare
`edge > limit - slack` silently dropped the last character.

## Catalogue module (`wisent_errors.codes`)

### Predicates and coercions

| function | returns |
|---|---|
| `code_or_none(text) → str \| None` | the honest primitive at a wire boundary, where "nothing was declared" and "something unknown was declared" must stay apart |
| `code_or_fallback(text) → str` | the code, or `FALLBACK` (`"unknown"`); never raises |

There is no `is_code`: `code_or_none(text) is not None` is the membership
test. Membership is `text in CODES` on a tuple of strings — Python has no
prototype chain to guard against.

### Derivations

| function | returns |
|---|---|
| `severity(code) → str` | `'warning'`, `'error'`, or `'critical'`, from `MEANINGS` |
| `retryable(code) → bool` | from `MEANINGS` |
| `outage(code) → bool` | from `MEANINGS` |
| `operator_summary(code) → str` | the catalogue's per-code sentence |
| `http_status(code) → int` | the edge status |
| `exit_code(code, chosen) → int` | `RETRY_EXIT` (69) when retryable, else `chosen` |
| `from_upstream_status(status) → str` | exact matches, then the inclusive 500–599 range → `infra_down`, else `unknown` |

The derivation functions index `MEANINGS[code]` directly and are not
guarded: handed an off-catalogue string they raise a bare `KeyError`.
Coerce with `code_or_fallback` or check with `code_or_none` first at wire
boundaries.

### Constants

| constant | value |
|---|---|
| `CODES` | tuple of the seven codes, catalogue order |
| `SEVERITIES` | the three severities in order (annotated `tuple[str, ...]`, generated as a list) |
| `MEANINGS` | per-code frozen dataclass: `operator_summary`, `retryable`, `outage`, `severity`, `http_status` |
| `FALLBACK` | `"unknown"` |
| `FAILURE_POINT_PATTERN` | the grammar, as a string |
| `RETRY_EXIT` | `69` |
| `DETAIL_LIMIT` | `2000` (main module only) |

## Executed

Every sentence above is exercised by
[examples/first_envelope.py](../examples/first_envelope.py); its captured
output is in [integrate/python](../integrate/python.md).
