#!/usr/bin/env node
// The JavaScript run from docs/integrate/js.md, runnable from a checkout:
//
//   node docs/examples/first-envelope.mjs
//
// A real consumer imports '@wisent/errors' / '@wisent/errors/codes' (pinned to a
// commit, see docs/quick-start.md); this script imports the same modules by path
// so it needs no npm install.

import { failure, failureOrFallback, render, chain } from '../../js/index.mjs';
import { fromUpstreamStatus, exitCode, isCode } from '../../js/codes.mjs';

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
