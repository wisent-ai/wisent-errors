// Real tests of `node ci/error-standard.mjs scan`: a tree with no generic
// sentence passes, a held sentence the baseline allows passes, a generic
// sentence beyond what the baseline allows is refused, and a baseline above
// what a file holds is refused. Each run's whole stdout and stderr are
// compared, and the `--json` report is read back as a document.
//
//   node --test tests/lint/scan.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const HELD = '    eprintln!("the push did not succeed");';
const REASON = 'says the operation failed without the step, the cause or the fix';

// `scan` over one case's src/main.rs holding `line` as its second line, with
// the baseline `baseline(file)` and the words `extra`, run from the root.
function scan(name, { line = HELD, baseline = () => ({}), extra = [] }) {
  const dir = join(root, 'target', 'real-tests', 'lint-scan', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, 'src'), { recursive: true });
  writeFileSync(join(dir, 'src', 'main.rs'), `fn main() {\n${line}\n}\n`);
  const file = relative(root, join(dir, 'src', 'main.rs'));
  const baselinePath = join(dir, 'baseline.json');
  writeFileSync(baselinePath, JSON.stringify(baseline(file)));
  try {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'scan', join(dir, 'src'), '--baseline', baselinePath, ...extra], { encoding: 'utf8', cwd: root });
    return { file, baselinePath, ran: { status: ran.status, stdout: ran.stdout, stderr: ran.stderr } };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// The three lines of a refusal of the scan's cause `id`.
const refusal = (id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.scan.${id}; ${PAGE}#wisent_errors-lint-scan-${id}\n`;

test('a_tree_without_a_generic_sentence_passes', () => {
  const { ran } = scan('clean', { line: '    eprintln!("pushing {branch}: the remote refused the ref");' });
  assert.deepEqual(ran, { status: EXIT_SUCCESS, stdout: '1 source file(s), 0 generic sentence(s), 0 refused, 0 stale baseline entries\n', stderr: '' });
});

test('a_held_sentence_the_baseline_allows_passes_and_is_reported', () => {
  const { ran } = scan('allowed', { baseline: (path) => ({ [path]: { 'did not succeed': 1 } }) });
  assert.deepEqual(ran, { status: EXIT_SUCCESS, stdout: '1 source file(s), 1 generic sentence(s), 0 refused, 0 stale baseline entries\n', stderr: '' });
  const json = scan('allowed-json', { baseline: (path) => ({ [path]: { 'did not succeed': 1 } }), extra: ['--json'] });
  assert.equal(json.ran.status, EXIT_SUCCESS, json.ran.stderr);
  assert.equal(json.ran.stderr, '');
  assert.deepEqual(JSON.parse(json.ran.stdout), {
    files: 1,
    findings: [{ path: json.file, line: 2, sentence: 'did not succeed', reason: REASON, text: HELD.trim() }],
    refused: [],
    stale: [],
  });
});

test('a_generic_sentence_beyond_the_baseline_is_refused', () => {
  const { file, ran } = scan('held', {});
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout:
      refusal(
        'generic-sentence-held',
        `holding ${file} to the error standard: line 2 says "did not succeed", which ${REASON}, and the baseline allows 0 of it in this file while it holds 1; observed: ${HELD.trim()}`,
        'declare the cause and raise it, saying what failed, why, the state observed and what fixes it, in place of the sentence',
      ) + '1 source file(s), 1 generic sentence(s), 1 refused, 0 stale baseline entries\n',
    stderr: '',
  });
});

test('a_baseline_above_what_a_file_holds_is_refused', () => {
  const { file, baselinePath, ran } = scan('stale', { baseline: (path) => ({ [path]: { 'did not succeed': 3 } }) });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout:
      refusal(
        'baseline-stale',
        `holding ${file} to the baseline ${baselinePath}: the baseline allows 3 of "did not succeed" in the file while it holds 1, and a baseline only shrinks; observed: 1 held, 3 allowed`,
        `lower the entry for ${file} in ${baselinePath} to 1`,
      ) + '1 source file(s), 1 generic sentence(s), 0 refused, 1 stale baseline entry\n',
    stderr: '',
  });
});
