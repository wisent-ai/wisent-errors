// Real tests of `node ci/no-handrolled-envelope.mjs`: a consuming tree that
// writes an envelope key by hand is listed line by line, a clean tree or a
// clean file says how many files it read, and this package's own source,
// where the keys belong, is never read. Each run's whole stdout and stderr
// are compared.
//
//   node --test tests/guard/handrolled.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const HAND_BUILT = 'export const report = { failure_point: point, error_code: code };';

const guard = (...paths) => {
  const ran = spawnSync(process.execPath, [join(root, 'ci', 'no-handrolled-envelope.mjs'), ...paths], { encoding: 'utf8' });
  return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
};

function inCase(name, body) {
  const dir = join(root, 'target', 'real-tests', 'guard-handrolled', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  try {
    return body(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a_hand_built_envelope_is_listed', () => {
  inCase('listed', (dir) => {
    writeFileSync(join(dir, 'failure.mjs'), `${HAND_BUILT}\n`);
    writeFileSync(join(dir, 'clean.mjs'), 'export const nothing = 1;\n');
    // A file of no source kind and a skipped directory are not read.
    writeFileSync(join(dir, 'notes.txt'), `${HAND_BUILT}\n`);
    mkdirSync(join(dir, 'node_modules'));
    writeFileSync(join(dir, 'node_modules', 'vendored.mjs'), `${HAND_BUILT}\n`);
    assert.deepEqual(guard(dir), {
      status: EXIT_FAILURE,
      stdout:
        `Error: reading 2 source file(s) under ${dir} for hand-built envelopes: 1 line(s) write failure_point or error_code outside the package, so their derived fields can drift from the catalogue; observed: 1 line(s) below\n` +
        "fix: build each envelope with wisent-errors; a log line already parsed, a field declaration or another API's own error_code is a reason to keep the line, and reading it decides which\n" +
        `cause: wisent_errors.lint.handrolled.envelope-key-written; ${PAGE}#wisent_errors-lint-handrolled-envelope-key-written\n` +
        `  ${join(dir, 'failure.mjs')}:1  ${HAND_BUILT}\n` +
        '\nEach needs a reason. Building an envelope here means the derived fields can be' +
        '\nwrong, so build it with wisent-errors instead. Three answers are legitimate and' +
        '\ncommon: an operator-visible log line whose format is already parsed, a field' +
        "\ndeclaration, and another API's own `error_code` -- Azure has one, and this guard" +
        '\ncannot tell it from ours. Read the line before believing the count.\n',
      stderr: '',
    });
  });
});

test('a_clean_tree_or_file_passes_naming_what_it_read', () => {
  inCase('clean', (dir) => {
    writeFileSync(join(dir, 'clean.mjs'), 'export const nothing = 1;\n');
    writeFileSync(join(dir, 'main.rs'), 'fn main() {}\n');
    assert.deepEqual(guard(dir), { status: EXIT_SUCCESS, stdout: `no hand-built envelope in 2 source file(s) under ${dir}\n`, stderr: '' });
    const file = join(dir, 'main.rs');
    assert.deepEqual(guard(file), { status: EXIT_SUCCESS, stdout: `no hand-built envelope in 1 source file(s) under ${file}\n`, stderr: '' });
  });
});

test('the_packages_own_source_is_never_read', () => {
  // js/index.mjs builds envelopes with failure_point and error_code keys.
  const own = join(root, 'js');
  assert.deepEqual(guard(own), { status: EXIT_SUCCESS, stdout: `no hand-built envelope in 0 source file(s) under ${own}\n`, stderr: '' });
});
