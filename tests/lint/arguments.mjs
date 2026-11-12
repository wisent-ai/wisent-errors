// Real tests of the declared layer `wisent_errors.lint.arguments`: this
// repository's commands started with no command, an unknown one, an option
// without its value, an option they do not have, or the wrong number of
// operands.
//
//   node --test tests/lint/arguments.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const run = (script, ...words) => spawnSync(process.execPath, [join(root, script), ...words], { encoding: 'utf8', cwd: root });

test('no_command_is_refused', () => {
  const result = run('ci/error-standard.mjs');
  assert.equal(result.status, 2);
  assert.match(result.stderr, /^Error: starting ci\/error-standard\.mjs: no command was named, and ci\/error-standard\.mjs does nothing without one; observed: commands: scan, catalogue, errors\nfix: name one of them: node ci\/error-standard\.mjs scan/);
  assert.match(result.stderr, /\ncause: wisent_errors\.lint\.arguments\.command-absent; https:\/\/github\.com\/wisent-ai\/wisent-errors\/blob\/main\/docs\/errors\/lint\.md#wisent_errors-lint-arguments-command-absent/);
});

test('an_unknown_command_is_refused', () => {
  const result = run('ci/error-standard.mjs', 'lint');
  assert.equal(result.status, 2);
  assert.match(result.stderr, /starting ci\/error-standard\.mjs: "lint" is not one of its commands; observed: commands: scan, catalogue, errors/);
});

test('an_option_without_its_value_is_refused', () => {
  const result = run('ci/warning-standard.mjs', 'warnings.json', '--confirmations');
  assert.equal(result.status, 2);
  assert.match(result.stderr, /reading the options of ci\/warning-standard\.mjs: --confirmations is the last word, or the word after it is another option, so it names nothing; observed: the words given: warnings\.json --confirmations/);
});

test('an_unknown_option_is_refused', () => {
  const result = run('ci/find-implementations.mjs', '--unadopted');
  assert.equal(result.status, 2);
  assert.match(result.stderr, /reading the options of ci\/find-implementations\.mjs: --unadopted is not one of its options, and nothing it does reads it; observed: the words given: --unadopted\nfix: drop --unadopted or spell it as one of its options: node ci\/find-implementations\.mjs \[<root>\.\.\.\] \[--unadopted-only\]/);
});

test('a_wrong_number_of_operands_is_refused', () => {
  const result = run('ci/warning-standard.mjs', 'a.json', 'b.json');
  assert.equal(result.status, 2);
  assert.match(result.stderr, /reading the operands of ci\/warning-standard\.mjs: it takes exactly one warnings catalogue and was given 2; observed: operands given: a\.json b\.json/);
  const inventory = run('tests/inventory.mjs');
  assert.equal(inventory.status, 2);
  assert.match(inventory.stderr, /it takes a revision, a pattern and at least one path and was given 0/);
});
