// Real tests of the declared layer `wisent_errors.lint.paths`: a tree a
// command of this repository is named to read that is absent, a file where a
// directory is read, or a directory it may not list. Before this layer, an
// absent tree was reported clean.
//
//   node --test tests/lint/paths.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const node = (script, ...words) => spawnSync(process.execPath, [join(root, script), ...words], { encoding: 'utf8' });
const place = (name) => {
  const dir = join(root, 'target', 'real-tests', 'lint-paths', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  return dir;
};

test('an_absent_path_is_refused', () => {
  const dir = place('absent');
  try {
    const result = node('ci/no-handrolled-envelope.mjs', join(dir, 'gone'));
    assert.equal(result.status, 2);
    assert.match(result.stderr, /^Error: opening the tree .*gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: .* exists and holds 0 entries/);
    assert.equal(result.stdout, '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a_file_named_as_a_directory_is_refused', () => {
  const dir = place('file');
  try {
    writeFileSync(join(dir, 'main.rs'), 'fn main() {}\n');
    const result = node('ci/error-standard.mjs', 'scan', join(dir, 'main.rs'));
    assert.equal(result.status, 2);
    assert.match(result.stderr, /the path is a file, and the source directory is read as a directory; observed: .*main\.rs is a file of 13 bytes.*\nfix: name the directory that holds it: /);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an_unreadable_path_is_refused', () => {
  const dir = place('unlisted');
  const locked = join(dir, 'src');
  try {
    mkdirSync(locked);
    chmodSync(locked, 0o000);
    const result = node('ci/error-standard.mjs', 'scan', dir);
    chmodSync(locked, 0o700);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /reading a source directory .*src: the operating system refused to list or read it, so what it holds was never looked at; observed: .*mode 0, .*EACCES/);
  } finally {
    chmodSync(locked, 0o700);
    rmSync(dir, { recursive: true, force: true });
  }
});
