// Real tests of the warning standard: ci/warning-standard.mjs run as the
// process a consuming repository runs, over a warnings catalogue and a
// repository written for each case, and the sentence a caller reads before
// confirming, from the runtime a JavaScript product imports. Each run's
// whole stdout and stderr are compared.
//
//   node --test tests/warnings/standard.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';
import { unconfirmed, warningsCatalogue } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const lint = join(root, 'ci', 'warning-standard.mjs');
const PAGE = 'https://example.wisent.com/docs/warnings';
const LINT_PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';

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

// One case's own repository under the ignored target/, removed after; the
// listing of each operation passes through `edit` before it is written.
function fixture(name, { operations, confirmations, tests, edit = (listed) => listed }) {
  const dir = join(root, 'target', 'real-tests', 'warnings', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const [path, text] of Object.entries(tests)) {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  const catalogue = join(dir, 'warnings.json');
  writeFileSync(catalogue, JSON.stringify({ functionalities: operations.map((operation) => edit(warningsCatalogue(operation, PAGE))) }));
  const confirming = join(dir, 'confirmations.json');
  writeFileSync(confirming, JSON.stringify(confirmations));
  return { dir, catalogue, confirming };
}

// `{ dir, confirming, ran }`: the case's paths and the run's status and streams.
function run(name, setup, extra = []) {
  const { dir, catalogue, confirming } = fixture(name, setup);
  try {
    const ran = spawnSync(process.execPath, [lint, catalogue, '--repository', dir, '--confirmations', confirming, ...extra], { encoding: 'utf8' });
    return { dir, confirming, ran: { status: ran.status, stdout: ran.stdout, stderr: ran.stderr } };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const HELD = { 'tests/purge/purge.sh': '# purge_without_yes_removes_nothing\n' };

// The three lines of a refusal of the warning check's cause `id`.
const refusal = (id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.warnings.${id}; ${LINT_PAGE}#wisent_errors-lint-warnings-${id}`;

// What the check prints for example.item.purge refused for `problems`, then its summary.
function refusedPurge(problems, summary) {
  const head = refusal(
    'warning-refused',
    `holding example.item.purge to the warning rules: ${problems.length} of its warning declarations break a rule, each named on its own line; observed: ${problems.length} line(s) below`,
    'change each declaration as its line says, then run the check again',
  );
  return (
    'FAIL  example.item.purge: 1 declared warning(s)\n' +
    `        ${head.split('\n').join('\n        ')}\n` +
    problems.map((problem) => `        ${problem}\n`).join('') +
    summary
  );
}

const ONE_REFUSED = '1 functionality, 1 declaring warnings, 1 refused; 0 confirmations with no declared warning\n';

test('a_declared_warning_with_its_confirmation_and_test_passes', () => {
  const { ran } = run('passes', { operations: [PURGE, LIST], confirmations: ['example purge'], tests: HELD });
  assert.deepEqual(ran, {
    status: EXIT_SUCCESS,
    stdout: 'ok    example.item.purge: 1 declared warning(s)\n2 functionalities, 1 declaring warnings, 0 refused; 0 confirmations with no declared warning\n',
    stderr: '',
  });
  const json = run('passes-json', { operations: [PURGE, LIST], confirmations: ['example purge'], tests: HELD }, ['--json']);
  assert.equal(json.ran.status, EXIT_SUCCESS, json.ran.stderr);
  assert.deepEqual(JSON.parse(json.ran.stdout), {
    operations: [
      { operation: 'example.item.purge', entries: ['example purge'], warnings: 1, problems: [] },
      { operation: 'example.item.list', entries: ['example list'], warnings: 0, problems: [] },
    ],
    unwarned: [],
  });
});

test('a_confirmation_no_warning_explains_is_refused', () => {
  const unwarned = { ...PURGE, warnings: [] };
  const { confirming, ran } = run('unwarned', { operations: [unwarned, LIST], confirmations: ['example purge'], tests: HELD });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout:
      `FAIL  ${refusal(
        'confirmation-unwarned',
        `matching the confirmations in ${confirming} to the declared warnings: the entry "example purge" asks for a confirmation, but no functionality it starts declares what the confirmation is for; observed: functionalities it starts: example.item.purge`,
        'declare the warning, or stop asking for a confirmation nothing needs',
      )}\n` + '2 functionalities, 0 declaring warnings, 0 refused; 1 confirmation with no declared warning\n',
    stderr: '',
  });
});

test('a_warning_no_confirmation_puts_before_its_caller_is_refused', () => {
  const { confirming, ran } = run('unconfirmed', { operations: [PURGE, LIST], confirmations: [], tests: HELD });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedPurge(
      [
        `operation example.item.purge: it declares 1 warning(s), but none of its entries (example purge) asks for a confirmation in ${confirming}, so the warning is never read before it runs; ask for one, or drop a warning nothing needs (warnings removed-for-good; ${confirming} lists no entry)`,
      ],
      '2 functionalities, 1 declaring warnings, 1 refused; 0 confirmations with no declared warning\n',
    ),
    stderr: '',
  });
});

test('a_warning_of_an_unknown_hazard_is_refused', () => {
  const odd = { ...PURGE, warnings: [{ ...PURGE_WARNING, hazard: 'scary' }] };
  const { ran } = run('hazard', { operations: [odd], confirmations: ['example purge'], tests: HELD });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedPurge(
      ['warning removed-for-good: hazard "scary" is not one of irreversible, overwrites, cuts-off-access, exposes-secret, external-change, costs-money; pick the loss the caller cannot take back'],
      ONE_REFUSED,
    ),
    stderr: '',
  });
});

test('a_warning_whose_test_the_repository_lacks_is_refused', () => {
  const { dir, ran } = run('untested', { operations: [PURGE], confirmations: ['example purge'], tests: {} });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedPurge(
      [
        `example.item.purge.removed-for-good names the test ${PURGE_WARNING.test}, which the repository does not hold: ${join(dir, 'tests', 'purge', 'purge.sh')} is absent; write that test, or name the one that shows this warning (repository ${dir})`,
      ],
      ONE_REFUSED,
    ),
    stderr: '',
  });
});

test('a_warning_with_an_empty_safeguard_is_refused', () => {
  const bare = { ...PURGE, warnings: [{ ...PURGE_WARNING, safeguard: ' ' }] };
  const { ran } = run('bare', { operations: [bare], confirmations: ['example purge'], tests: HELD });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedPurge(['warning removed-for-good: `safeguard` is empty; write what keeps a way back, done before confirming'], ONE_REFUSED),
    stderr: '',
  });
});

test('a_warning_without_its_page_anchor_or_declared_twice_is_refused', () => {
  const twice = { ...PURGE, warnings: [PURGE_WARNING, PURGE_WARNING] };
  const unanchored = (listed) => ({ ...listed, warnings: listed.warnings.map((warning, index) => (index === 0 ? { ...warning, doc: PAGE } : warning)) });
  const { ran } = run('anchor', { operations: [twice], confirmations: ['example purge'], tests: HELD, edit: unanchored });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedPurge(
      [
        `operation example.item.purge: warning removed-for-good links doc "${PAGE}", which is not an anchor on an https warnings page; print ${PAGE}#example-item-purge-warning-removed-for-good, as the runtime's warnings listing writes it`,
        'operation example.item.purge: warning removed-for-good is declared twice; keep one declaration per id',
      ],
      '1 functionality, 1 declaring warnings, 1 refused; 0 confirmations with no declared warning\n',
    ).replace('1 declared warning(s)', '2 declared warning(s)'),
    stderr: '',
  });
});

test('an_unconfirmed_caller_reads_the_effect_the_loss_the_way_back_and_how_to_go_ahead', () => {
  assert.equal(
    unconfirmed(PURGE_WARNING, { id: 'github' }),
    'github and every saved version of it are removed; nothing restores them, not restore and not restore --at; nothing was done. ' +
      'Before confirming: keep a copy with `example backup <directory>`, which `example backup restore` puts back. To go ahead: rerun with --yes',
  );
});
