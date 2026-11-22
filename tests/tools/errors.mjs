// Real test of `node ci/error-standard.mjs errors [--json]`, the command that
// prints this package's own failure catalogue as any product's `errors list
// --json` prints its own (docs/errors/lint.md, `wisent_errors.lint.catalogue`,
// "Started through: ... `node ci/error-standard.mjs errors`"); a consuming
// repository and the docs read it to learn every refusal the package's
// commands can give.
//
//   node --test tests/tools/errors.mjs
//
// Rule 4: `errors` is this package's own command, started here as the
// process a reader starts, with process.execPath, from a directory of the
// case's own; what it reads is the package's real catalogue under
// catalogue/failures/, the parts the commands raise from, with nothing
// seeded in their place. It has no service, store or network to reach.
// Rule 5: the state `errors` answers for is the catalogue on disk, so each
// listing is compared with the parts read back from catalogue/failures/:
// every functionality the parts declare for node, in path order, with its
// uses and every cause tested in JavaScript, and in --json every declared
// field of every cause (code, usage, failed, cause, observed, remedy, test)
// as its part states it. After every step the parts are read back byte for
// byte (the command writes nothing), the case's directory and home empty.
// Rule 6: `errors` reads the catalogue and its words, and every answer is a
// step: the listing as text, the listing as JSON, an operand it does not
// take and an option it does not have, each refusal compared whole. The
// parts loader's refusals of a catalogue it cannot read are
// tests/tools/parts.mjs, run on a copy of the package broken step by step.
// Rule 7: one test, the whole story of `errors`.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/tools-errors-<pid>/home; the
// command has no backend and no variable of its own.
// Rule 9: the loader's own line, the inventory's revision-unknown cause and
// both refusals were copied from `errors` run by hand with `env -i`.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const failures = join(root, 'catalogue', 'failures');
const LINT_PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const TOOLS_PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const USAGE =
  'node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json] | ' +
  'catalogue <catalogue.json> [--repository <dir>] [--sources <path>,...] [--entries <entries.json>] [--json] | errors [--json]';
// The statuses `errors` answered: the catalogue printed, a refusal of how it was started.
const EXIT_SUCCESS = 0;
const USAGE_EXIT = 2;
// The parts loader declares its own causes in code (codegen/parts.mjs), first in every listing.
const LOADER = 'wisent_errors.catalogue.parts: parts-unlisted, parts-absent, part-unreadable, part-not-json, part-wrong-shape, operation-declared-twice, uses-undeclared, raised-undeclared\n';

// The child's whole environment: PATH, and a home, temporary directory and XDG directories inside the case.
const isolated = (home) => ({
  PATH: process.env.PATH,
  HOME: home,
  TMPDIR: home,
  XDG_CONFIG_HOME: join(home, '.config'),
  XDG_CACHE_HOME: join(home, '.cache'),
  XDG_DATA_HOME: join(home, '.local', 'share'),
  XDG_STATE_HOME: join(home, '.local', 'state'),
});

// Every part of the catalogue at any depth, by its path below catalogue/failures/, with what it holds.
const parts = () =>
  Object.fromEntries(
    readdirSync(failures, { recursive: true })
      .filter((name) => name.endsWith('.json'))
      .sort()
      .map((name) => [name, readFileSync(join(failures, name), 'utf8')]),
  );

// The functionalities the parts declare for node, in the order of their paths, each keeping the causes tested in JavaScript.
const declared = (held) =>
  Object.values(held).flatMap((text) =>
    JSON.parse(text)
      .operations.filter((operation) => operation.runtimes.includes('node'))
      .map((operation) => ({ ...operation, causes: operation.causes.filter((cause) => cause.tests.js !== undefined) })),
  );

test('errors_lists_the_packages_own_catalogue_as_its_parts_declare_it', () => {
  const dir = join(root, 'target', 'real-tests', `tools-errors-${process.pid}`);
  const home = join(dir, 'home');
  const work = join(dir, 'work');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  mkdirSync(work, { recursive: true });
  const held = parts();
  const operations = declared(held);
  const errors = (...words) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'errors', ...words], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(parts(), held, `${step}: every part of the catalogue is left as it was`);
    assert.deepEqual(readdirSync(work), [], `${step}: nothing is written where the command runs`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    assert.ok(operations.length > 0, 'the parts declare functionalities run in node');
    assert.deepEqual(errors(), {
      status: EXIT_SUCCESS,
      stdout: LOADER + operations.map((operation) => `${operation.id}: ${operation.causes.map((cause) => cause.id).join(', ') || `uses ${operation.uses.join(', ')}`}\n`).join(''),
      stderr: '',
    });
    untouched('the listing');

    const ran = errors('--json');
    assert.equal(ran.status, EXIT_SUCCESS);
    assert.equal(ran.stderr, '');
    const listed = JSON.parse(ran.stdout);
    assert.equal(ran.stdout, `${JSON.stringify(listed, null, 2)}\n`, 'the listing is printed as indented JSON');
    assert.deepEqual(
      listed.slice(1).map((operation) => ({
        id: operation.operation,
        entries: operation.entries,
        uses: operation.uses,
        summary: operation.summary,
        docs: operation.docs,
        causes: operation.causes.map(({ id, code, usage, failed, cause, observed, remedy, test: named }) => ({ id, code, usage, failed, cause, observed, remedy, test: named })),
      })),
      operations.map((operation) => ({
        id: operation.id,
        entries: operation.entries,
        uses: operation.uses,
        summary: operation.summary,
        docs: operation.docs,
        causes: operation.causes.map(({ id, code, usage, failed, cause, observed, remedy, tests }) => ({ id, code, usage, failed, cause, observed, remedy, test: tests.js })),
      })),
      'every functionality and cause is listed as its part declares it',
    );
    assert.deepEqual(
      listed[0].causes.map((cause) => `${cause.id} ${cause.code} exit ${cause.exit}`),
      LOADER.trim().split(': ')[1].split(', ').map((id) => `${id} config exit 1`),
      "the loader's causes are config, and each exits with EXIT_FAILURE",
    );
    assert.deepEqual(
      listed.find((operation) => operation.operation === 'wisent_errors.inventory.list').causes[0],
      {
        id: 'revision-unknown',
        code: 'not_found',
        exit: USAGE_EXIT,
        retryable: false,
        usage: true,
        failed: 'listing the lines of {revision} that match {quoted_pattern}',
        cause: 'git knows no revision {revision} in {repository}',
        observed: 'git exited {status} and said {stderr}',
        remedy: 'name a commit, tag or branch the checkout holds; `git -C {repository} fetch` brings one it lacks',
        test: 'tests/tools/inventory.mjs::inventory_lists_a_revisions_matching_lines_or_refuses_what_git_cannot_read',
        doc: `${TOOLS_PAGE}#wisent_errors-inventory-list-revision-unknown`,
      },
      'a listed cause carries its exit, whether it is retried and its anchor on the page',
    );
    untouched('the listing as JSON');

    assert.deepEqual(errors('stado'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr:
        'Error: reading the operands of ci/error-standard.mjs: it takes no operand and was given 1; observed: operands given: stado\n' +
        `fix: name no operand: ${USAGE}\n` +
        `cause: wisent_errors.lint.arguments.operands-miscounted; ${LINT_PAGE}#wisent_errors-lint-arguments-operands-miscounted\n`,
    });
    untouched('an operand');

    assert.deepEqual(errors('--all'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr:
        'Error: reading the options of ci/error-standard.mjs: --all is not one of its options, and nothing it does reads it; observed: the words given: errors --all\n' +
        `fix: drop --all or spell it as one of its options: ${USAGE}\n` +
        `cause: wisent_errors.lint.arguments.option-unknown; ${LINT_PAGE}#wisent_errors-lint-arguments-option-unknown\n`,
    });
    untouched('an option it does not have');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
