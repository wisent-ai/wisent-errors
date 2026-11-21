// Real tests of `node ci/find-implementations.mjs`: a repository restating
// the vocabulary is counted and refused, one that declares the package is
// listed with its pin and passes, a stale checkout of a product that no
// longer restates it and one with no remote are told apart from one that
// does, a file the census cannot read is refused instead of skipped, and a
// census with no git to ask is refused. Each run's whole stdout and stderr
// are compared.
//
//   node --test tests/tools/census.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const COPY = "export const CODES = ['config', 'auth', 'not_found', 'rate_limit', 'timeout', 'infra_down'];\n";
const CLEAN = "export const greeting = 'hello';\n";
const PIN = '0123456789abcdef0123456789abcdef01234567';
// 8 codes in catalogue/codes.json, so a file counts from 5 of them; COPY quotes 6.
const SUMMARY = (declared, rows, live, stale, part) =>
  `\n${declared} checkout(s) declare a dependency on the package.\n${rows} still quote 5 or more codes as literals: ${live} restate the taxonomy, ${stale} are stale or detached copies of one that does not, ${part} are part-migrated and name the package too.\n`;

// One case's own product under the ignored target/: a git repository holding
// `committed`, whose origin is itself when `remote`, so the census can read
// the remote tip, then `working` written over it uncommitted; git is kept off
// the operator's configuration by a home of its own. With `fromPackage`,
// the census is a copy of this package beside the product, started with no
// root, so it searches the copy's parent, the case's directory.
function census(name, { committed = { 'failure.mjs': COPY }, working = {}, remote = true, setup = () => {}, words = [], env = null, fromPackage = false }) {
  const dir = join(root, 'target', 'real-tests', 'tools-census', `${name}-${process.pid}`);
  const product = join(dir, 'product');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(product, { recursive: true });
  const isolated = { PATH: process.env.PATH, HOME: dir, TMPDIR: dir, GIT_CONFIG_NOSYSTEM: '1' };
  const git = (...gitWords) => assert.equal(spawnSync('git', ['-C', product, ...gitWords], { env: isolated }).status, 0, `git ${gitWords.join(' ')}`);
  for (const [path, text] of Object.entries(committed)) writeFileSync(join(product, path), text);
  git('init', '-q', '-b', 'main');
  git('add', '.');
  git('-c', 'user.name=Juniper Vale', '-c', 'user.email=juniper@example.invalid', 'commit', '-q', '-m', 'the product');
  if (remote) {
    git('remote', 'add', 'origin', product);
    git('fetch', '-q', 'origin');
  }
  for (const [path, text] of Object.entries(working)) writeFileSync(join(product, path), text);
  const expected = setup(dir, product);
  let script = join(root, 'ci', 'find-implementations.mjs');
  let operands = [dir, ...words];
  if (fromPackage) {
    for (const part of ['ci', 'codegen', 'js', 'catalogue']) cpSync(join(root, part), join(dir, 'package', part), { recursive: true });
    script = join(dir, 'package', 'ci', 'find-implementations.mjs');
    operands = words;
  }
  try {
    const ran = spawnSync(process.execPath, [script, ...operands], { encoding: 'utf8', env: env ?? isolated });
    return { dir, product, label: `${name}-${process.pid}/product`, expected, ran: { status: ran.status, stdout: ran.stdout, stderr: ran.stderr } };
  } finally {
    if (existsSync(join(product, 'failure.mjs'))) chmodSync(join(product, 'failure.mjs'), 0o600); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    rmSync(dir, { recursive: true, force: true });
  }
}

// The three lines of a refusal of the census's cause `id`.
const refusal = (id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.census.implementations.${id}; ${PAGE}#wisent_errors-census-implementations-${id}\n`;

test('a_repository_restating_the_vocabulary_is_counted', () => {
  const { dir, label, ran } = census('restated', {});
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout:
      `RESTATES  ${label}  (1 file(s))\n         failure.mjs  names 6/8\n\n` +
      SUMMARY(0, 1, 1, 0, 0) +
      refusal(
        'vocabulary-restated',
        `counting the implementations of the envelope under ${dir}: 1 repositories quote a majority of the catalogue's codes, infra_down among them, and depend on no revision of the package; observed: each repository with the files that restate it, a file counting when it quotes 5 or more of the 8 codes: ${label} (failure.mjs names 6/8)`,
        'adopt the package in each, pinned to a revision, and delete its copy of the vocabulary from the files named; `node ci/find-implementations.mjs --unadopted-only` lists them again',
      ),
    stderr: '',
  });
});

test('without_a_root_the_parent_of_the_package_is_searched_and_the_package_left_out', () => {
  const { dir, label, ran } = census('default-root', { fromPackage: true });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout:
      `RESTATES  ${label}  (1 file(s))\n         failure.mjs  names 6/8\n\n` +
      SUMMARY(0, 1, 1, 0, 0) +
      refusal(
        'vocabulary-restated',
        `counting the implementations of the envelope under ${dir}: 1 repositories quote a majority of the catalogue's codes, infra_down among them, and depend on no revision of the package; observed: each repository with the files that restate it, a file counting when it quotes 5 or more of the 8 codes: ${label} (failure.mjs names 6/8)`,
        'adopt the package in each, pinned to a revision, and delete its copy of the vocabulary from the files named; `node ci/find-implementations.mjs --unadopted-only` lists them again',
      ),
    stderr: '',
  });
});

test('a_repository_declaring_the_package_is_listed_with_its_pin_and_passes', () => {
  const manifest = JSON.stringify({ name: 'example-product', dependencies: { '@wisent/errors': `github:wisent-ai/wisent-errors#${PIN}` } });
  const adopted = `import { failure } from '@wisent/errors';\n${COPY}`;
  const { label, ran } = census('adopted', { committed: { 'package.json': manifest, 'failure.mjs': adopted } });
  assert.deepEqual(ran, {
    status: EXIT_SUCCESS,
    stdout: `adopted   ${label}  (1 file(s))\n  +      failure.mjs  names 6/8\n\ndeclares  ${label}  pin ${PIN}\n` + SUMMARY(1, 1, 0, 0, 1),
    stderr: '',
  });
  // --unadopted-only leaves out what adopted and the declarations.
  const only = census('adopted-only', { committed: { 'package.json': manifest, 'failure.mjs': adopted }, words: ['--unadopted-only'] });
  assert.deepEqual(only.ran, { status: EXIT_SUCCESS, stdout: SUMMARY(1, 1, 0, 0, 1), stderr: '' });
});

test('a_manifest_naming_the_package_without_a_revision_is_listed_unpinned', () => {
  const manifest = JSON.stringify({ name: 'example-product', dependencies: { '@wisent/errors': 'github:wisent-ai/wisent-errors' } });
  const { label, ran } = census('unpinned', { committed: { 'package.json': manifest, 'failure.mjs': CLEAN } });
  assert.deepEqual(ran, { status: EXIT_SUCCESS, stdout: `\ndeclares  ${label}  pin unpinned\n` + SUMMARY(1, 0, 0, 0, 0), stderr: '' });
});

test('a_stale_or_detached_checkout_is_not_counted_as_restating', () => {
  // The remote tip no longer restates the vocabulary; the checkout still does.
  const stale = census('stale', { committed: { 'failure.mjs': CLEAN }, working: { 'failure.mjs': COPY } });
  assert.deepEqual(stale.ran, { status: EXIT_SUCCESS, stdout: `stale     ${stale.label}  (1 file(s))\n         failure.mjs  names 6/8\n\n` + SUMMARY(0, 1, 0, 1, 0), stderr: '' });
  const detached = census('detached', { remote: false });
  assert.deepEqual(detached.ran, { status: EXIT_SUCCESS, stdout: `detached  ${detached.label}  (1 file(s))\n         failure.mjs  names 6/8\n\n` + SUMMARY(0, 1, 0, 1, 0), stderr: '' });
});

test('an_unreadable_file_is_refused', () => {
  const { dir, expected, ran } = census('unreadable', {
    setup: (_, product) => {
      const path = join(product, 'failure.mjs');
      chmodSync(path, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
      const entry = statSync(path);
      let answered = null;
      try {
        readFileSync(path, 'utf8');
      } catch (error) {
        answered = error.message;
      }
      return { path, state: `${path} is a file of ${entry.size} bytes, mode ${(entry.mode & 0o777).toString(8)}, owner uid ${entry.uid}`, answered };
    },
  });
  assert.notEqual(expected.answered, null, 'the file is refused to this process too');
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: '',
    stderr: refusal(
      'file-unreadable',
      `reading ${expected.path} while counting the implementations under ${dir}: the operating system refused the read, so whether it restates the vocabulary or declares the package is unknown; observed: ${expected.state}; the operating system answered ${expected.answered}`,
      `let the user running the census read it (chmod u+r ${expected.path}), or name roots that leave it out`,
    ),
  });
});

test('a_census_without_git_is_refused', () => {
  const { product, ran } = census('no-git', { env: { PATH: '' } });
  const started = spawnSync('git', ['--version'], { env: { PATH: '' } });
  assert.notEqual(started.error, undefined, 'git cannot be started with an empty PATH');
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: '',
    stderr: refusal(
      'git-absent',
      `asking git where ${product} came from and what its remote tip holds: no git program could be started, so a stale checkout cannot be told from a product that restates the vocabulary; observed: PATH holds ""; starting git answered ${started.error.message}`,
      'install git or put it on PATH, then count again',
    ),
  });
});
