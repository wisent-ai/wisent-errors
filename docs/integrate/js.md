# Integrating the JavaScript runtime

The npm package is `@wisent/errors`, defined by the `package.json` at the
repository root — deliberately at the root, because npm has no way to install
from a subdirectory of a git repository. Two entry points: the main module
(builders, render, chain, trims, plus re-exported catalogue functions) and
`@wisent/errors/codes` (the generated catalogue module alone, "what a product
imports when it wants only the derived values and keeps its own renderer,
which is most of the fleet"). TypeScript declarations ship in `js/index.d.ts`
and `js/codes.d.ts`; the package carries zero dependencies.

## Install

Pin the exact commit in the dependency spec itself, not just the lockfile:

```json
"dependencies": {
  "@wisent/errors": "github:wisent-ai/wisent-errors#<sha>"
}
```

A local checkout works the same with `"file:../wisent-errors"`, which is how
the run below was produced.

## A complete example, executed

`demo.mjs` — every call surface a typical consumer touches:

```js
import { failure, failureOrFallback, render, chain, raise, FailureError } from '@wisent/errors';
import { fromUpstreamStatus, httpStatus, exitCode, isCode, codeOrFallback } from '@wisent/errors/codes';

const refused = failure({
  failurePoint: 'toy.gateway.oauth-refresh',
  code: 'auth',
  service: 'toy',
  impact: 'one credential refresh',
  detail: 'invalid_grant -- Refresh token not found or invalid',
});
const throttled = failure({
  failurePoint: 'toy.dispatch.bounded-rotation',
  code: 'rate_limit',
  service: 'toy',
  impact: 'one model request',
  detail: "all bounded 'claude-code' credentials unavailable for agent",
  cause: refused,
});

console.log('render:', render(throttled));
for (const row of chain(throttled)) console.log('  ' + row);
console.log('fromUpstreamStatus(429):', fromUpstreamStatus(429));
console.log('exitCode("rate_limit", 2):', exitCode('rate_limit', 2));
console.log('isCode("toString"):', isCode('toString'));

try {
  failure({ failurePoint: 'Not A Point', code: 'auth', service: 'toy' });
} catch (error) {
  console.log('strict refusal:', error.constructor.name + ':', error.message);
}

const salvaged = failureOrFallback({ failurePoint: 'Not A Point', code: 'panic', service: '' });
console.log('salvaged:', JSON.stringify(salvaged));
```

Run against this repository (`npm install` with the dependency above, then
`node demo.mjs`) it prints, verbatim:

```
render: an upstream is throttling us — the request or its credentials; retry later {"failure_point":"toy.dispatch.bounded-rotation","error_code":"rate_limit","service":"toy","impact":"one model request","severity":"warning","retryable":true,"outage":false,"detail":"all bounded 'claude-code' credentials unavailable for agent","cause":{"failure_point":"toy.gateway.oauth-refresh","error_code":"auth","service":"toy","impact":"one credential refresh","severity":"warning","retryable":false,"outage":false,"detail":"invalid_grant -- Refresh token not found or invalid"}}
  toy.dispatch.bounded-rotation [rate_limit] all bounded 'claude-code' credentials unavailable for agent
  toy.gateway.oauth-refresh [auth] invalid_grant -- Refresh token not found or invalid
fromUpstreamStatus(429): rate_limit
exitCode("rate_limit", 2): 69
isCode("toString"): false
strict refusal: TypeError: failurePoint "Not A Point" is not a dotted lowercase path
salvaged: {"failure_point":"Not A Point","error_code":"unknown","service":"unknown","impact":null,"severity":"error","retryable":false,"outage":false,"detail":null,"context":{"wisent_errors.failure_point":"malformed","wisent_errors.error_code":"off-catalogue: panic","wisent_errors.service":"absent"}}
```

The runnable script is [examples/first-envelope.mjs](../examples/first-envelope.mjs).

## Wiring it into a service

- **Error paths use the salvage builder.** `failureOrFallback` never throws;
  four web products had reporters that threw on hostile values (a getter
  that raises, a revoked `Proxy`) inside React error boundaries. Violations
  travel as `wisent_errors.*` context keys instead of exceptions inside a
  `catch`.
- **`cause` accepts a `FailureError` directly.** Both builders unwrap
  `cause instanceof FailureError` to its `.envelope`, so
  `catch (error) { failure({ ..., cause: error }) }` works when the layer
  below raised through this package.
- **Answer HTTP edges with `httpStatus`, classify upstreams with
  `fromUpstreamStatus`.** A working end-to-end service doing both, with
  captured curl output, is [walkthrough-adoption](../walkthrough-adoption.md).
- **Keep your trim width.** `trimDetail(text, limit)` — the width is your
  product's decision; 2000 (`DETAIL_LIMIT`) is only the package's own bound.

## JS-specific behaviour worth knowing

- Envelopes are plain objects — no class, no prototype tricks; `context` is
  shallow-copied.
- The strict builder's field errors are `TypeError`s with the exact sentences
  `failurePoint must be a non-empty string`, `service must be a non-empty
  string`, `detail must be a non-empty string` (a provided `detail` must be a
  non-empty string; omit it or pass `null` for none).
- Membership predicates (`isCode`, `codeOrNull`, `codeOrFallback`) answer
  through a `Set` — `toString`, `__proto__`, `constructor`,
  `hasOwnProperty`, `valueOf` are all refused, which the conformance table
  probes by name ([conformance](../conformance.md)).
- `raise(fields)` throws `FailureError`, whose `message` is
  `<failure_point>: <detail or operator summary>` and whose `envelope`
  carries the data.

## Guard your tree

After migrating, run the guard from a checkout of this package:

```bash
node ci/no-handrolled-envelope.mjs <your-source-tree>
```

Exit 0 is clean; the full contract of the guard is in
[reference/tools](../reference/tools.md). Full API: [reference/js](../reference/js.md).
