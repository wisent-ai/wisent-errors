// Real tests of the declaration rules a JavaScript product's causes are held
// to, through the runtime it imports: a placeholder the renderer never fills,
// a cause that only wraps the raw text below it, raw text outside `observed`,
// and the probes catalogue/declaration.json states for every runtime.
//
//   node --test tests/declaration/placeholders.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PROBES, causeProblems, fill, isPlaceholderName, parts, unfilled, warningProblems } from '../../js/index.mjs';
import { CAUSE_ID, TEST_PATH } from '../../js/operation.mjs';

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
  assert.equal(problems.length, 3, problems.join('\n'));
  assert.match(problems[0], /`failed` holds the placeholder \{Path\}, .* write \{path\}/);
  assert.match(problems[1], /`failed` holds the placeholder \{deal\.title\}, .* write \{deal_title\}/);
  assert.match(problems[2], /`remedy` opens a placeholder at "\{name before passing it" that no '\}' closes; close it as \{name\} or drop the '\{'/);
  assert.match(causeProblems({ ...CAUSE, failed: 'checking a} value' })[0], /`failed` holds a '\}' at "checking a\} value" that no '\{' opened/);
});

test('a_cause_whose_why_is_only_the_raw_message_is_refused', () => {
  const problems = causeProblems({ ...CAUSE, cause: '{error}' });
  assert.ok(problems.includes("cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`"), problems.join('\n'));
  assert.ok(problems.some((problem) => problem.startsWith('cause value-unsafe: `cause` is only "{error}", the text it wraps, so it says nothing of why')), problems.join('\n'));
  assert.ok(causeProblems({ ...CAUSE, cause: '{code}: {reason}' }).some((problem) => problem.includes('`cause` is only "{code}: {reason}"')));
  assert.deepEqual(causeProblems({ ...CAUSE, observed: 'the parser said {problem}' }), []);
});

test('a_warning_holding_a_placeholder_the_renderer_never_fills_is_refused', () => {
  const warning = { id: 'removed', hazard: 'irreversible', effect: '{id:?} is removed', consequence: 'nothing restores it', safeguard: 'keep a copy', confirm: 'rerun with --yes', test: 'tests/purge/purge.sh::purge_asks' };
  assert.match(warningProblems(warning)[0], /^warning removed: `effect` holds the placeholder \{id:\?\}, which the renderer never fills/);
});

test('the_renderer_reads_a_template_as_every_runtime_does', () => {
  assert.deepEqual(parts('a {x} {Y} {z'), [{ text: 'a ' }, { placeholder: 'x' }, { text: ' ' }, { malformed: '{Y}' }, { text: ' ' }, { unclosed: '{z' }]);
  assert.deepEqual(unfilled(['{a} {b}', '{b} {c}'], { b: '1' }), ['a', 'c']);
  for (const name of PROBES.placeholder.valid) assert.ok(isPlaceholderName(name), name);
  for (const name of PROBES.placeholder.invalid) assert.ok(!isPlaceholderName(name), name);
  for (const id of PROBES.cause_id.valid) assert.ok(CAUSE_ID.test(id), id);
  for (const id of PROBES.cause_id.invalid) assert.ok(!CAUSE_ID.test(id), id);
  for (const path of PROBES.test_path.valid) assert.ok(TEST_PATH.test(path), path);
  for (const path of PROBES.test_path.invalid) assert.ok(!TEST_PATH.test(path), path);
});
