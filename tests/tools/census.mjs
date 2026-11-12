// Real tests of `node ci/find-implementations.mjs`: a repository restating
// the vocabulary is counted and refused, a file the census cannot read is
// refused instead of skipped, and a census with no git to ask is refused.
//
//   node --test tests/tools/census.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const COPY = "export const CODES = ['config', 'auth', 'not_found', 'rate_limit', 'timeout', 'infra_down'];\n";

// One case's own product: a git repository whose origin is itself, so the
// census can read the remote tip, with git kept off the operator's
// configuration by a home of its own.
function census(name, setup, env = null) {
  const dir = join(root, 'target', 'real-tests', 'tools-census', `${name}-${process.pid}`);
  const product = join(dir, 'product');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(product, { recursive: true });
  writeFileSync(join(product, 'failure.mjs'), COPY);
  const isolated = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: '1' };
  const git = (...words) => assert.equal(spawnSync('git', ['-C', product, ...words], { env: isolated }).status, 0, `git ${words.join(' ')}`);
  git('init', '-q', '-b', 'main');
  git('add', 'failure.mjs');
  git('-c', 'user.name=census', '-c', 'user.email=census@example.invalid', 'commit', '-q', '-m', 'restates the vocabulary');
  git('remote', 'add', 'origin', product);
  git('fetch', '-q', 'origin');
  setup(dir);
  try {
    return spawnSync(process.execPath, [join(root, 'ci', 'find-implementations.mjs'), dir], { encoding: 'utf8', env: env ?? isolated });
  } finally {
    chmodSync(join(product, 'failure.mjs'), 0o600);
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a_repository_restating_the_vocabulary_is_counted', () => {
  const result = census('restated', () => {});
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /Error: counting the implementations of the envelope under .*: 1 repositories quote a majority of the catalogue's codes, infra_down among them, and depend on no revision of the package; observed: .*product/);
});

test('an_unreadable_file_is_refused', () => {
  const result = census('unreadable', (dir) => chmodSync(join(dir, 'product', 'failure.mjs'), 0o000));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /reading .*failure\.mjs while counting the implementations under .*: the operating system refused the read, so whether it restates the vocabulary or declares the package is unknown; observed: .*mode 0, .*EACCES/);
});

test('a_census_without_git_is_refused', () => {
  const result = census('no-git', () => {}, { PATH: '' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /asking git where .*product came from and what its remote tip holds: no git program could be started/);
});
