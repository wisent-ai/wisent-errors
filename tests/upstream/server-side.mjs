// Defect 89D58BED: the catalogue classified 501 Not Implemented and 505 HTTP
// Version Not Supported against each other. Both say the server does not
// support what we sent it — a request our deployment shaped — so both are
// `config`, our failure that retrying will not mend; every other 5xx is an
// upstream that is down. Read through the package's own entry point, as a
// consumer reads it.
// https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
//
// Usage: node --test tests/upstream/server-side.mjs
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
