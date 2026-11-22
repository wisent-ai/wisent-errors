// The catalogue used to classify 501 Not Implemented and 505 HTTP Version Not
// Supported against each other. Both say the server does not support what
// we sent it -- a request our deployment shaped -- so both are `config`, our
// failure that retrying will not mend; every other 5xx is an upstream that
// is down or slow. https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
//
//   node --test tests/upstream/server-side.mjs
//
// Rule 4: what is defended is the JavaScript runtime's classification of an
// upstream's HTTP status, and its product is the package's public entry
// point, js/index.mjs, imported exactly as a consuming JavaScript product
// imports it (`import { fromUpstreamStatus } from '@wisent/errors'`, whose
// "exports" in package.json is that file). No program of this package runs
// it: the classification is a pure function a product calls while it builds
// its own failure, with no process, file, store or network of its own, so
// there is no binary to start and no other component to stand in for; a
// consumer program wrapping the call would only print the same returned
// code. The commands of this package (ci/, codegen/) are tested as processes
// in tests/lint, tests/tools, tests/guard and tests/warnings.
// Rule 5: the returned code and what the catalogue says of it (whose failure
// it is, whether a retry mends it, whether it is an outage) are the whole of
// the state the classification has; each is asserted exactly, for each
// status, against the catalogue's own words.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fromUpstreamStatus, outage, retryable, whose } from '../../js/index.mjs';

test('not_implemented_and_version_not_supported_are_one_class', () => {
  for (const status of [501, 505]) {
    const code = fromUpstreamStatus(status);
    assert.equal(code, 'config', String(status));
    assert.equal(whose(code), 'our failure');
    assert.equal(retryable(code), false);
    assert.equal(outage(code), true);
  }
});

test('the_other_server_errors_stay_apart', () => {
  assert.equal(fromUpstreamStatus(500), 'infra_down');
  assert.equal(fromUpstreamStatus(502), 'infra_down');
  assert.equal(fromUpstreamStatus(503), 'infra_down');
  assert.equal(fromUpstreamStatus(504), 'timeout');
});
