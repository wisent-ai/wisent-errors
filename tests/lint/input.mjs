// Real tests of the declared layer `wisent_errors.lint.input`: a JSON file a
// command of this repository is named that is absent, a directory, not
// readable, not JSON, or not the document it should be. Each case writes its
// own files under the ignored target/ and removes them after.
//
//   node --test tests/lint/input.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const lint = join(root, 'ci', 'error-standard.mjs');

function inCase(name, files, body) {
  const dir = join(root, 'target', 'real-tests', 'lint-input', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const [path, text] of Object.entries(files)) writeFileSync(join(dir, path), text);
  try {
    return body(dir);
  } finally {
    chmodSync(dir, 0o700);
    rmSync(dir, { recursive: true, force: true });
  }
}

const catalogue = (path) => spawnSync(process.execPath, [lint, 'catalogue', path], { encoding: 'utf8' });

test('an_absent_input_is_refused', () => {
  inCase('absent', {}, (dir) => {
    const result = catalogue(join(dir, 'errors.json'));
    assert.equal(result.status, 2);
    assert.match(result.stderr, /^Error: reading the catalogue .*errors\.json: no file is at that path; observed: .* exists and holds 0 entries\nfix: name the file that holds the catalogue, or write it first/);
  });
});

test('a_directory_input_is_refused', () => {
  inCase('directory', {}, (dir) => {
    const result = catalogue(dir);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /the path names a directory, and the catalogue is one file; observed: .* is a directory, mode 7\d\d/);
  });
});

test('an_input_the_process_may_not_read_is_refused', () => {
  inCase('unreadable', { 'errors.json': '[]' }, (dir) => {
    chmodSync(join(dir, 'errors.json'), 0o000);
    const result = catalogue(join(dir, 'errors.json'));
    chmodSync(join(dir, 'errors.json'), 0o600);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /the file exists but its permissions refuse this process the read; observed: .* is a file of 2 bytes, mode 0, owner uid \d+; the operating system answered EACCES/);
  });
});

test('an_input_that_is_not_json_is_refused', () => {
  inCase('syntax', { 'errors.json': '[{"operation": ' }, (dir) => {
    const result = catalogue(join(dir, 'errors.json'));
    assert.equal(result.status, 1);
    assert.match(result.stderr, /reading the catalogue .*: the file is not JSON; observed: 15 bytes, starting "\[\{\\"operation\\": "; the decoder answered /);
  });
});

test('an_input_of_the_wrong_shape_is_refused', () => {
  inCase('shape', { 'errors.json': '{"functionalities": []}' }, (dir) => {
    const result = catalogue(join(dir, 'errors.json'));
    assert.equal(result.status, 1);
    assert.match(result.stderr, /the file is JSON but not a list of functionalities, or an object with operations; observed: it holds an object with functionalities/);
  });
});
