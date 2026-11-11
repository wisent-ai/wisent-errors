// A vendor that answers 402 Payment Required refuses the account the
// credential belongs to until that account pays: the failure is the
// credential's side and repeating the call repeats the refusal. It used to
// fall to `unknown`, so a Supabase restore refused for unpaid invoices read
// as a failure no one could attribute. Read through the package's own entry
// point, as a consumer reads it.
//
// Usage: node --test tests/upstream/payment-required.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fromUpstreamStatus, retryable, whose } from '../../js/index.mjs';

test('payment_required_is_the_credentials_account', () => {
  const code = fromUpstreamStatus(402);
  assert.equal(code, 'auth');
  assert.equal(whose(code), 'the credentials the request presented');
  assert.equal(retryable(code), false);
});

test('payment_required_stays_apart_from_its_neighbours', () => {
  assert.equal(fromUpstreamStatus(400), 'unknown');
  assert.equal(fromUpstreamStatus(401), 'auth');
  assert.equal(fromUpstreamStatus(403), 'auth');
  assert.equal(fromUpstreamStatus(404), 'not_found');
});
