// Real tests of the declaration rules a JavaScript product's causes are held
// to, through the runtime it imports: a placeholder the renderer never fills,
// a cause that only wraps the raw text below it, raw text outside `observed`,
// and the probes catalogue/declaration.json states for every runtime.
//
//   node --test tests/declaration/placeholders.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PROBES, causeProblems, fill, isPlaceholderName, parts, unfilled, warningProblems } from '../../js/index.mjs';
import { CAUSE_ID, TEST_PATH } from '../../js/declared/operation.mjs';

const CAUSE = {
  id: 'value-unsafe',
  code: 'refused',
  usage: false,
  failed: 'checking the value {name}',
  cause: 'the value holds a quote the engine would read as the end of the string',
  observed: 'value {value}',
  remedy: 'quote {name} before passing it',
  test: 'tests/engine/values.rs::an_unsafe_value_is_refused',
};

test('a_format_spec_placeholder_is_refused_naming_the_cause_and_the_placeholder', () => {
  const problems = causeProblems({ ...CAUSE, observed: 'value {value:?}' });
  assert.deepEqual(problems, [
    "cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted",
  ]);
  assert.equal(fill('value {value:?}', { value: 'x', 'value:?': 'y' }), 'value {value:?}');
});

test('every_placeholder_the_renderer_will_not_fill_is_refused', () => {
  const texts = { failed: 'checking {Path} and {deal.title}', remedy: 'quote {name before passing it' };
  const problems = causeProblems({ ...CAUSE, ...texts });
  const malformed = (kind, field, placeholder, suggestion) =>
    `${kind}: \`${field}\` holds the placeholder ${placeholder}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write ${suggestion} and have the raising site pass the value already formatted`;
  assert.deepEqual(problems, [
    malformed('cause value-unsafe', 'failed', '{Path}', '{path}'),
    malformed('cause value-unsafe', 'failed', '{deal.title}', '{deal_title}'),
    "cause value-unsafe: `remedy` opens a placeholder at \"{name before passing it\" that no '}' closes; close it as {name} or drop the '{'",
  ]);
  assert.deepEqual(causeProblems({ ...CAUSE, failed: 'checking a} value' }), [
    "cause value-unsafe: `failed` holds a '}' at \"checking a} value\" that no '{' opened; drop it, or open the placeholder it ends",
  ]);
});

test('a_cause_whose_why_is_only_the_raw_message_is_refused', () => {
  const wraps = (quoted) => `cause value-unsafe: \`cause\` is only ${quoted}, the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into \`observed\``;
  assert.deepEqual(causeProblems({ ...CAUSE, cause: '{error}' }), [
    "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
    wraps('"{error}"'),
  ]);
  assert.deepEqual(causeProblems({ ...CAUSE, cause: '{code}: {reason}' }), [wraps('"{code}: {reason}"')]);
  assert.deepEqual(causeProblems({ ...CAUSE, observed: 'the parser said {problem}' }), []);
});

test('a_warning_holding_a_placeholder_the_renderer_never_fills_is_refused', () => {
  const warning = { id: 'removed', hazard: 'irreversible', effect: '{id:?} is removed', consequence: 'nothing restores it', safeguard: 'keep a copy', confirm: 'rerun with --yes', test: 'tests/purge/purge.sh::purge_asks' };
  assert.deepEqual(warningProblems(warning), ["warning removed: `effect` holds the placeholder {id:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {id} and have the raising site pass the value already formatted"]);
});

test('the_renderer_reads_a_template_as_every_runtime_does', () => {
  assert.deepEqual(parts('a {x} {Y} {z'), [{ text: 'a ' }, { placeholder: 'x' }, { text: ' ' }, { malformed: '{Y}' }, { text: ' ' }, { unclosed: '{z' }]);
  assert.deepEqual(unfilled(['{a} {b}', '{b} {c}'], { b: '1' }), ['a', 'c']);
  for (const name of PROBES.placeholder.valid) assert.ok(isPlaceholderName(name), name);
  for (const name of PROBES.placeholder.invalid) assert.ok(!isPlaceholderName(name), name);
  for (const id of PROBES.cause_id.valid) assert.ok(CAUSE_ID.test(id), id);
  for (const id of PROBES.cause_id.invalid) assert.ok(!CAUSE_ID.test(id), id);
  for (const path of PROBES.test_path.valid) assert.deepEqual(causeProblems({ ...CAUSE, test: path }), [], path);
  for (const path of PROBES.test_path.invalid) {
    assert.deepEqual(causeProblems({ ...CAUSE, test: path }), [
      `cause value-unsafe: test ${JSON.stringify(path)} is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it`,
    ], path);
  }
});
