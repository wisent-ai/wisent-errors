// Real tests of `node tests/inventory.mjs`'s refusals: a revision git does
// not know, a pattern it does not read, no git to start, and a checkout that
// is no git repository.
//
//   node --test tests/tools/inventory.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const list = (words, options = {}) => spawnSync(process.execPath, [join(options.root ?? root, 'tests', 'inventory.mjs'), ...words], { encoding: 'utf8', env: options.env ?? process.env });

test('an_unknown_revision_is_refused', () => {
  const result = list(['no-such-revision', 'x', 'README.md']);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /^Error: listing the lines of no-such-revision that match "x": git knows no revision no-such-revision in .*; observed: git exited 128 and said fatal: /);
});

test('a_pattern_git_refuses_is_refused', () => {
  const result = list(['HEAD', 'a(', 'README.md']);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /git does not read "a\(" as an extended regular expression; observed: git exited 128/);
});

test('a_listing_without_git_is_refused', () => {
  const result = list(['HEAD', 'x', 'README.md'], { env: { PATH: '' } });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /no git program could be started; observed: PATH ; starting git answered spawnSync git ENOENT/);
});

test('a_listing_outside_a_repository_is_refused', () => {
  const copy = join(root, 'target', 'real-tests', 'tools-inventory', `${process.pid}`);
  rmSync(copy, { recursive: true, force: true });
  mkdirSync(copy, { recursive: true });
  try {
    for (const part of ['tests', 'ci', 'codegen', 'js', 'catalogue']) cpSync(join(root, part), join(copy, part), { recursive: true });
    const result = list(['HEAD', 'x', 'README.md'], { root: copy, env: { ...process.env, GIT_CEILING_DIRECTORIES: resolve(copy, '..') } });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /holds no git repository, as an unpacked archive of the source does not/);
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
});
