// What `causeOf` says of a caught value: the message and every cause under
// it once, a value that is no Error as text, and a chain that loops ending; an
// object JSON cannot say as it is, and an empty message, said without a throw
// or an empty sentence.
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
  // https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6.4
  assert.equal(causeOf(new Error('refused', { cause: { status: 503 } })), 'refused: {"status":503}');
});

test('a_chain_that_comes_back_to_itself_ends', () => {
  const first = new Error('first');
  const second = new Error('second', { cause: first });
  first.cause = second;
  assert.equal(causeOf(first), 'first: second');
});

test('an_object_that_holds_itself_or_a_bigint_is_said_without_a_throw', () => {
  const row = { id: 7n, table: 'orders' };
  row.self = row;
  assert.equal(causeOf(row), '{"id":"7","table":"orders","self":"[Circular]"}');
  const shared = { status: 503 };
  assert.equal(causeOf({ first: shared, second: shared }), '{"first":{"status":503},"second":{"status":503}}');
});

test('an_empty_message_says_no_empty_sentence', () => {
  assert.equal(causeOf(new Error('', { cause: new Error('disk full') })), 'disk full');
  assert.equal(causeOf(new TypeError('')), 'TypeError');
  assert.equal(causeOf(new Error('waited: timeout', { cause: 'timeout' })), 'waited: timeout');
});
