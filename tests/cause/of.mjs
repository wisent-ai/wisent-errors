// What `causeOf` says of a caught value: the message and every cause under
// it once, a value that is no Error as text, and a chain that loops ending.
//
//   node --test tests/cause/of.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { causeOf } from '../../js/index.mjs';

test('a_failed_fetch_names_the_cause_its_message_leaves_out', () => {
  const refused = Object.assign(new Error('connect ECONNREFUSED 127.0.0.1:5432'), { code: 'ECONNREFUSED' });
  const failed = new TypeError('fetch failed', { cause: refused });
  assert.equal(causeOf(failed), 'fetch failed: connect ECONNREFUSED 127.0.0.1:5432');
});

test('a_cause_its_message_already_says_is_said_once', () => {
  const inner = new Error('disk full');
  const outer = new Error('writing state.json: disk full', { cause: inner });
  assert.equal(causeOf(outer), 'writing state.json: disk full');
});

test('a_value_that_is_no_error_is_said_as_text', () => {
  assert.equal(causeOf({ message: 'JWT expired', code: 'PGRST301' }), '{"message":"JWT expired","code":"PGRST301"}');
  assert.equal(causeOf('timeout'), 'timeout');
  assert.equal(causeOf(undefined), 'undefined');
  assert.equal(causeOf(new Error('refused', { cause: { status: 503 } })), 'refused: {"status":503}');
});

test('a_chain_that_comes_back_to_itself_ends', () => {
  const first = new Error('first');
  const second = new Error('second', { cause: first });
  first.cause = second;
  assert.equal(causeOf(first), 'first: second');
});
