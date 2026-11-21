// Real tests of the declared layer `wisent_errors.lint.paths`: a tree a
// command of this repository is named to read that is absent, a file where a
// directory is read, or a directory it may not list. Before this layer, an
// absent tree was reported clean. Each refusal is the whole of stderr, its
// three lines compared; what the operating system answers is read by asking
// it the same way, and the state observed is read from the case's own files.
//
//   node --test tests/lint/paths.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE } from '../../ci/support/refuse.mjs';
import { USAGE_EXIT } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const node = (script, ...words) => {
  const ran = spawnSync(process.execPath, [join(root, script), ...words], { encoding: 'utf8' });
  return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
};
const place = (name) => {
  const dir = join(root, 'target', 'real-tests', 'lint-paths', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  return dir;
};

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
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.paths.${id}; ${PAGE}#wisent_errors-lint-paths-${id}\n`,
});

test('an_absent_path_is_refused', () => {
  const dir = place('absent');
  try {
    const gone = join(dir, 'gone');
    assert.deepEqual(
      node('ci/no-handrolled-envelope.mjs', gone),
      refused(
        USAGE_EXIT,
        'path-absent',
        `opening the tree ${gone}: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${dir} exists and holds 0 entries`,
        `name the tree as it exists; a relative path is read from ${process.cwd()}`,
      ),
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a_file_named_as_a_directory_is_refused', () => {
  const dir = place('file');
  try {
    const file = join(dir, 'main.rs');
    writeFileSync(file, 'fn main() {}\n');
    assert.deepEqual(
      node('ci/error-standard.mjs', 'scan', file),
      refused(
        USAGE_EXIT,
        'path-not-directory',
        `opening the source directory ${file}: the path is a file, and the source directory is read as a directory; observed: ${state(file)}`,
        `name the directory that holds it: ${dir}`,
      ),
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an_unreadable_path_is_refused', () => {
  const dir = place('unlisted');
  const locked = join(dir, 'src');
  try {
    mkdirSync(locked);
    chmodSync(locked, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const ran = node('ci/error-standard.mjs', 'scan', dir);
    let answered = null;
    try {
      readdirSync(locked, { withFileTypes: true });
    } catch (error) {
      answered = error.message;
    }
    const observed = `${state(locked)}; the operating system answered ${answered}`;
    chmodSync(locked, 0o700); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.notEqual(answered, null, 'the locked directory is refused to this process too');
    assert.deepEqual(
      ran,
      refused(
        EXIT_FAILURE,
        'path-unreadable',
        `reading a source directory ${locked}: the operating system refused to list or read it, so what it holds was never looked at; observed: ${observed}`,
        `let the user running the command read it (chmod u+rx ${locked}), or leave it out of the paths named`,
      ),
    );
  } finally {
    chmodSync(locked, 0o700); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    rmSync(dir, { recursive: true, force: true });
  }
});
