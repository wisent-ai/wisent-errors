// Real tests of the warning standard: ci/warning-standard.mjs run as the
// process a consuming repository runs, over a warnings catalogue and a
// repository written for each case, and the sentence a caller reads before
// confirming, from the runtime a JavaScript product imports.
//
//   node --test tests/warnings/standard.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { unconfirmed, warningsCatalogue } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const lint = join(root, 'ci', 'warning-standard.mjs');
const PAGE = 'https://example.wisent.com/docs/warnings';

const PURGE_WARNING = {
  id: 'removed-for-good',
  hazard: 'irreversible',
  effect: '{id} and every saved version of it are removed',
  consequence: 'nothing restores them, not restore and not restore --at',
  safeguard: 'keep a copy with `example backup <directory>`, which `example backup restore` puts back',
  confirm: 'rerun with --yes',
  test: 'tests/purge/purge.sh::purge_without_yes_removes_nothing',
};

const PURGE = {
  id: 'example.item.purge',
  entries: ['example purge'],
  uses: [],
  summary: 'remove a trashed item and every saved version for good',
  docs: 'https://example.wisent.com/docs/errors',
  causes: [],
  warnings: [PURGE_WARNING],
};

const LIST = {
  id: 'example.item.list',
  entries: ['example list'],
  uses: [],
  summary: 'list item metadata',
  docs: 'https://example.wisent.com/docs/errors',
  causes: [],
  warnings: [],
};

// One case's own repository under the ignored target/, removed after.
function fixture(name, { operations, confirmations, tests }) {
  const dir = join(root, 'target', 'real-tests', 'warnings', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const [path, text] of Object.entries(tests)) {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  const catalogue = join(dir, 'warnings.json');
  writeFileSync(catalogue, JSON.stringify({ functionalities: operations.map((operation) => warningsCatalogue(operation, PAGE)) }));
  const confirming = join(dir, 'confirmations.json');
  writeFileSync(confirming, JSON.stringify(confirmations));
  return { dir, catalogue, confirming };
}

function run(name, setup) {
  const { dir, catalogue, confirming } = fixture(name, setup);
  try {
    return spawnSync('node', [lint, catalogue, '--repository', dir, '--confirmations', confirming], { encoding: 'utf8' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const HELD = { 'tests/purge/purge.sh': '# purge_without_yes_removes_nothing\n' };

test('a_declared_warning_with_its_confirmation_and_test_passes', () => {
  const result = run('passes', { operations: [PURGE, LIST], confirmations: ['example purge'], tests: HELD });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /2 functionalities, 1 declaring warnings, 0 refused; 0 confirmations with no declared warning/);
});

test('a_confirmation_no_warning_explains_is_refused', () => {
  const unwarned = { ...PURGE, warnings: [] };
  const result = run('unwarned', { operations: [unwarned, LIST], confirmations: ['example purge'], tests: HELD });
  assert.equal(result.status, 1);
  assert.match(
    result.stdout,
    /FAIL {2}Error: matching the confirmations in .*confirmations\.json to the declared warnings: the entry "example purge" asks for a confirmation, but no functionality it starts declares what the confirmation is for; observed: functionalities it starts: example\.item\.purge\nfix: declare the warning, or stop asking for a confirmation nothing needs/,
  );
});

test('a_warning_no_confirmation_puts_before_its_caller_is_refused', () => {
  const result = run('unconfirmed', { operations: [PURGE, LIST], confirmations: [], tests: HELD });
  assert.equal(result.status, 1);
  assert.match(
    result.stdout,
    /it declares 1 warning\(s\), but none of its entries \(example purge\) asks for a confirmation in .*confirmations\.json, so the warning is never read before it runs; ask for one, or drop a warning nothing needs/,
  );
});

test('a_warning_of_an_unknown_hazard_is_refused', () => {
  const odd = { ...PURGE, warnings: [{ ...PURGE_WARNING, hazard: 'scary' }] };
  const result = run('hazard', { operations: [odd], confirmations: ['example purge'], tests: HELD });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /warning removed-for-good: hazard "scary" is not one of irreversible, overwrites, cuts-off-access, exposes-secret, external-change, costs-money/);
});

test('a_warning_whose_test_the_repository_lacks_is_refused', () => {
  const result = run('untested', { operations: [PURGE], confirmations: ['example purge'], tests: {} });
  assert.equal(result.status, 1);
  assert.match(
    result.stdout,
    /example\.item\.purge\.removed-for-good names the test tests\/purge\/purge\.sh::purge_without_yes_removes_nothing, which the repository does not hold: .*tests\/purge\/purge\.sh is absent; write that test, or name the one that shows this warning/,
  );
});

test('a_warning_with_an_empty_safeguard_is_refused', () => {
  const bare = { ...PURGE, warnings: [{ ...PURGE_WARNING, safeguard: ' ' }] };
  const result = run('bare', { operations: [bare], confirmations: ['example purge'], tests: HELD });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /warning removed-for-good: `safeguard` is empty/);
});

test('an_unconfirmed_caller_reads_the_effect_the_loss_the_way_back_and_how_to_go_ahead', () => {
  assert.equal(
    unconfirmed(PURGE_WARNING, { id: 'github' }),
    'github and every saved version of it are removed; nothing restores them, not restore and not restore --at; nothing was done. ' +
      'Before confirming: keep a copy with `example backup <directory>`, which `example backup restore` puts back. To go ahead: rerun with --yes',
  );
});
