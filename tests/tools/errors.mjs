// Real tests of `node ci/error-standard.mjs errors`: this package's own
// failure catalogue printed one functionality per line and as the JSON every
// product's `errors list --json` prints, read against the parts in
// catalogue/failures/ it is joined from, and an operand it does not take
// refused. Each run's whole stdout and stderr are compared.
//
//   node --test tests/tools/errors.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';
import { USAGE_EXIT } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const failures = join(root, 'catalogue', 'failures');
const LINT_PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const TOOLS_PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const USAGE =
  'node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json] | ' +
  'catalogue <catalogue.json> [--repository <dir>] [--sources <path>,...] [--entries <entries.json>] [--json] | errors [--json]';

const errors = (...words) => {
  const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'errors', ...words], { encoding: 'utf8' });
  return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
};

// The functionalities the commands of this repository declare, as the parts
// on disk state them: the parts loader's own first, then every part's
// operations run in node, in the order of the parts' paths at any depth
// below catalogue/failures/, each keeping the causes tested in JavaScript.
function declared() {
  const operations = [
    {
      id: 'wisent_errors.catalogue.parts',
      uses: [],
      causes: ['parts-unlisted', 'parts-absent', 'part-unreadable', 'part-not-json', 'part-wrong-shape', 'operation-declared-twice', 'uses-undeclared', 'raised-undeclared'],
    },
  ];
  for (const name of readdirSync(failures, { recursive: true }).filter((file) => file.endsWith('.json')).sort()) {
    for (const operation of JSON.parse(readFileSync(join(failures, name), 'utf8')).operations) {
      if (!operation.runtimes.includes('node')) continue;
      operations.push({ id: operation.id, uses: operation.uses, causes: operation.causes.filter((cause) => cause.tests.js !== undefined).map((cause) => cause.id) });
    }
  }
  return operations;
}

test('the_packages_own_catalogue_is_listed', () => {
  const lines = declared().map((operation) => `${operation.id}: ${operation.causes.join(', ') || `uses ${operation.uses.join(', ')}`}\n`);
  assert.deepEqual(errors(), { status: EXIT_SUCCESS, stdout: lines.join(''), stderr: '' });
});

test('the_packages_own_catalogue_is_listed_as_json', () => {
  const ran = errors('--json');
  assert.equal(ran.status, EXIT_SUCCESS, ran.stderr);
  assert.equal(ran.stderr, '');
  const listed = JSON.parse(ran.stdout);
  assert.deepEqual(
    listed.map((operation) => ({ id: operation.operation, uses: operation.uses, causes: operation.causes.map((cause) => cause.id) })),
    declared(),
  );
  const inventory = listed.find((operation) => operation.operation === 'wisent_errors.inventory.list');
  assert.deepEqual(inventory.causes.find((cause) => cause.id === 'revision-unknown'), {
    id: 'revision-unknown',
    code: 'not_found',
    exit: USAGE_EXIT,
    retryable: false,
    usage: true,
    failed: 'listing the lines of {revision} that match {quoted_pattern}',
    cause: 'git knows no revision {revision} in {repository}',
    observed: 'git exited {status} and said {stderr}',
    remedy: 'name a commit, tag or branch the checkout holds; `git -C {repository} fetch` brings one it lacks',
    test: 'tests/tools/inventory.mjs::an_unknown_revision_is_refused',
    doc: `${TOOLS_PAGE}#wisent_errors-inventory-list-revision-unknown`,
  });
  // The loader's causes are `config`, neither usage nor retryable and of no status of their own: each exits with EXIT_FAILURE.
  const parts = listed.find((operation) => operation.operation === 'wisent_errors.catalogue.parts');
  assert.deepEqual(parts.causes.map((cause) => cause.exit), parts.causes.map(() => EXIT_FAILURE));
});

test('an_operand_errors_does_not_take_is_refused', () => {
  assert.deepEqual(errors('stado'), {
    status: USAGE_EXIT,
    stdout: '',
    stderr:
      'Error: reading the operands of ci/error-standard.mjs: it takes no operand and was given 1; observed: operands given: stado\n' +
      `fix: name no operand: ${USAGE}\n` +
      `cause: wisent_errors.lint.arguments.operands-miscounted; ${LINT_PAGE}#wisent_errors-lint-arguments-operands-miscounted\n`,
  });
});
