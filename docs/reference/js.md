# JavaScript API reference

Package `@wisent/errors` (`js/index.mjs`, types in `js/index.d.ts`); subpath
`@wisent/errors/codes` (`js/codes.mjs`, types in `js/codes.d.ts`) exports the
generated catalogue module alone. The main module re-exports everything from
`/codes`, so one import serves both. Zero dependencies. All refusal
sentences below are the exact strings thrown by the code.

## Builders

### `failure({ failurePoint, code, service, impact, detail, cause, context }) → Envelope`

Builds an envelope as a plain object with `severity`, `retryable`, `outage`
filled from the catalogue. Throws `TypeError` on anything malformed:

| condition | exact sentence |
|---|---|
| `failurePoint` not a non-empty string | `failurePoint must be a non-empty string` |
| `failurePoint` fails the grammar | `failurePoint <json> is not a dotted lowercase path` |
| `code` not in the catalogue | `code <json> is not in the catalogue; one of config, auth, not_found, rate_limit, timeout, infra_down, unknown` |
| `service` not a non-empty string | `service must be a non-empty string` |
| `detail` provided but not a non-empty string | `detail must be a non-empty string` |

`failurePoint` and `service` are trimmed. `impact` is optional: any value is
stringified and trimmed, empty becomes `null`. `detail` omitted or `null`
serializes as `null`; provided, it is trimmed to `DETAIL_LIMIT` (2000).
`cause` may be an envelope or a `FailureError` (unwrapped to its
`.envelope`); `context` is shallow-copied and omitted when empty.

### `failureOrFallback(fields = {}) → Envelope`

The same, but it never throws. Coercions, each recorded in `context`:

| violation | result | context note |
|---|---|---|
| `failurePoint` absent/empty | `"unknown"` | `wisent_errors.failure_point: "absent"` |
| `failurePoint` malformed | kept verbatim | `wisent_errors.failure_point: "malformed"` |
| `code` absent | `"unknown"` | `wisent_errors.error_code: "absent"` |
| `code` off-catalogue | `"unknown"` | `wisent_errors.error_code: "off-catalogue: <text>"` |
| `service` absent/empty | `"unknown"` | `wisent_errors.service: "absent"` |

Caller-provided `context` merges under the notes (notes win on collision).

### `raise(fields) → never`

`throw new FailureError(failure(fields))`.

### `class FailureError extends Error`

`name` is `'FailureError'`; `envelope` carries the data; `message` is
`<failure_point>: <detail ?? operatorSummary(error_code)>`.

## Rendering

### `render(envelope) → string`

One line: `<operatorSummary> — <whose><retry> <JSON>` where `<whose>` is
`our failure` / `the request or its credentials` (from `outage`) and
`<retry>` is `; retry later` / `; retrying will not help` (from
`retryable`). The JSON is `JSON.stringify(envelope)`.

### `chain(envelope) → string[]`

One row per cause-chain layer, outermost first:
`<failure_point> [<error_code>] <detail ?? '-'>`.

## Trims

### `trimDetail(text, limit = DETAIL_LIMIT) → string`

Stringifies (`String(text ?? '')`), strips whitespace at both ends, cuts
hard at `limit`. The width is an argument because it is a product decision;
the rule is the shared part.

### `trimDetailAtWordEdge(text, limit = DETAIL_LIMIT, slack = 24) → string`

The same, cut back to the last space when one falls within `slack`
characters of the bound; the result is right-trimmed. Opt-in, because it
changes emitted bytes. The `edge > 0` guard matters: `lastIndexOf` returns
-1 when there is no space at all, and for any limit under `slack` a bare
`edge > limit - slack` silently dropped the last character.

## Catalogue module (`@wisent/errors/codes`)

### Predicates and coercions

| function | returns |
|---|---|
| `isCode(text) → boolean` | whether the catalogue knows this text; a type guard in TS; answered through a `Set`, so `toString`, `__proto__` etc. are refused |
| `codeOrNull(text) → Code \| null` | the honest primitive at a wire boundary, where "nothing was declared" and "something unknown was declared" must stay apart |
| `codeOrFallback(text) → Code` | the code, or `FALLBACK` (`"unknown"`); never throws |

### Derivations

| function | returns |
|---|---|
| `severity(code) → 'warning' \| 'error' \| 'critical'` | from `MEANINGS` |
| `retryable(code) → boolean` | from `MEANINGS` |
| `outage(code) → boolean` | from `MEANINGS` |
| `operatorSummary(code) → string` | the catalogue's per-code sentence |
| `httpStatus(code) → number` | the edge status |
| `exitCode(code, chosen) → number` | `RETRY_EXIT` (69) when retryable, else `chosen` |
| `fromUpstreamStatus(status) → Code` | exact matches, then the inclusive 500–599 range → `infra_down`, else `unknown` |

The derivation functions index `MEANINGS[code]` directly and are not
guarded: handed an off-catalogue string they throw a bare `TypeError`
(reading properties of `undefined`). Validate with `isCode` or coerce with
`codeOrFallback` first at wire boundaries.

### Constants

| constant | value |
|---|---|
| `CODES` | frozen array of the seven codes, catalogue order |
| `SEVERITIES` | frozen `["warning","error","critical"]` |
| `MEANINGS` | frozen per-code record: `operatorSummary`, `retryable`, `outage`, `severity`, `httpStatus` |
| `FALLBACK` | `"unknown"` |
| `FAILURE_POINT_PATTERN` | the grammar, as a string |
| `RETRY_EXIT` | `69` |
| `DETAIL_LIMIT` | `2000` (main module only) |

## TypeScript

`js/index.d.ts` declares `Code` and `Severity` unions, `Envelope`, `Context`
(`Record<string, string | number | boolean | null>`), strict `Fields`, and
`SalvageableFields` (every field `unknown`, by design — "the fields the
never-throwing builder accepts: anything"). `isCode` narrows to `Code`.
