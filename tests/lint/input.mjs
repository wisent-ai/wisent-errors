// Real tests of the declared layer `wisent_errors.lint.input`: a JSON file a
// command of this repository is named that is absent, a directory, not
// readable, not JSON, or not the document it should be. Each case writes its
// own files under the ignored target/ and removes them after. Each refusal is
// the whole of stderr, its three lines compared; what the operating system
// and JSON.parse answer is read by asking them the same way, and the state
// observed (a mode, an owner, a listing) is read from the case's own files.
//
//   node --test tests/lint/input.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE } from '../../ci/support/refuse.mjs';
import { USAGE_EXIT } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const lint = join(root, 'ci', 'error-standard.mjs');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const EXPECTED = 'a list of functionalities, or an object with operations';

function inCase(name, files, body) {
  const dir = join(root, 'target', 'real-tests', 'lint-input', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const [path, text] of Object.entries(files)) writeFileSync(join(dir, path), text);
  try {
    return body(dir);
  } finally {
    chmodSync(dir, 0o700); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    rmSync(dir, { recursive: true, force: true });
  }
}

const catalogue = (path) => {
  const ran = spawnSync(process.execPath, [lint, 'catalogue', path], { encoding: 'utf8' });
  return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
};

// What the operating system or the decoder answers `attempt` with.
function answered(attempt) {
  try {
    attempt();
  } catch (error) {
    return error.message;
  }
  throw new Error('the attempt was to fail');
}

// `path` as stat reads it: its kind, its permission bits and its owner.
function state(path) {
  const entry = statSync(path);
  const kind = entry.isDirectory() ? 'a directory' : `a file of ${entry.size} bytes`;
  return `${path} is ${kind}, mode ${(entry.mode & 0o777).toString(8)}, owner uid ${entry.uid}`;
}

// The whole run of a refusal of the layer's cause `id`.
const refused = (status, id, sentence, remedy) => ({
  status,
  stdout: '',
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.input.${id}; ${PAGE}#wisent_errors-lint-input-${id}\n`,
});

test('an_absent_input_is_refused', () => {
  inCase('absent', {}, (dir) => {
    const path = join(dir, 'errors.json');
    assert.deepEqual(
      catalogue(path),
      refused(
        USAGE_EXIT,
        'input-absent',
        `reading the catalogue ${path}: no file is at that path; observed: ${dir} exists and holds 0 entries`,
        `name the file that holds the catalogue, or write it first; a relative path is read from ${process.cwd()}`,
      ),
    );
  });
});

test('a_directory_input_is_refused', () => {
  inCase('directory', {}, (dir) => {
    assert.deepEqual(
      catalogue(dir),
      refused(
        USAGE_EXIT,
        'input-is-directory',
        `reading the catalogue ${dir}: the path names a directory, and the catalogue is one file; observed: ${state(dir)}`,
        'name the JSON file inside it, not the directory',
      ),
    );
  });
});

test('an_input_the_process_may_not_read_is_refused', () => {
  inCase('unreadable', { 'errors.json': '[]' }, (dir) => {
    const path = join(dir, 'errors.json');
    chmodSync(path, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const ran = catalogue(path);
    const observed = `${state(path)}; the operating system answered ${answered(() => readFileSync(path, 'utf8'))}`;
    chmodSync(path, 0o600); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(
      ran,
      refused(
        EXIT_FAILURE,
        'input-not-permitted',
        `reading the catalogue ${path}: the file exists but its permissions refuse this process the read; observed: ${observed}`,
        `let the user running the command read it (chmod u+r ${path}), or run the command as its owner`,
      ),
    );
    assert.equal(readFileSync(path, 'utf8'), '[]', 'the refused input is left as it was');
  });
});

test('an_input_that_is_not_json_is_refused', () => {
  const text = '[{"operation": ';
  inCase('syntax', { 'errors.json': text }, (dir) => {
    const path = join(dir, 'errors.json');
    // The decoder stops at the end of the one line: position 15, line 1, column 16.
    const stop = `line 1, column 16: ${JSON.stringify(text)}`;
    assert.deepEqual(
      catalogue(path),
      refused(
        EXIT_FAILURE,
        'input-not-json',
        `reading the catalogue ${path}: the file is not JSON; observed: 15 bytes, starting ${JSON.stringify(text)}; the decoder answered ${answered(() => JSON.parse(text))}, stopping at ${stop}`,
        `write the catalogue as JSON (${EXPECTED}), correcting ${path} at ${stop}`,
      ),
    );
  });
});

test('an_input_of_the_wrong_shape_is_refused', () => {
  inCase('shape', { 'errors.json': '{"functionalities": []}' }, (dir) => {
    const path = join(dir, 'errors.json');
    assert.deepEqual(
      catalogue(path),
      refused(
        EXIT_FAILURE,
        'input-wrong-shape',
        `reading the catalogue ${path}: the file is JSON but not ${EXPECTED}; observed: it holds an object with functionalities`,
        `write the catalogue as ${EXPECTED}`,
      ),
    );
  });
});
