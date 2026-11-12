// Real tests of `node ci/error-standard.mjs scan`: a generic sentence beyond
// what the baseline allows, and a baseline above what a file holds.
//
//   node --test tests/lint/scan.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');

function scan(name, baseline) {
  const dir = join(root, 'target', 'real-tests', 'lint-scan', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, 'src'), { recursive: true });
  writeFileSync(join(dir, 'src', 'main.rs'), 'fn main() {\n    eprintln!("the push did not succeed");\n}\n');
  const file = relative(root, join(dir, 'src', 'main.rs'));
  writeFileSync(join(dir, 'baseline.json'), JSON.stringify(baseline(file)));
  try {
    return { file, result: spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'scan', join(dir, 'src'), '--baseline', join(dir, 'baseline.json')], { encoding: 'utf8', cwd: root }) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a_generic_sentence_beyond_the_baseline_is_refused', () => {
  const { file, result } = scan('held', () => ({}));
  assert.equal(result.status, 1);
  assert.ok(
    result.stdout.includes(`Error: holding ${file} to the error standard: line 2 says "did not succeed", which says the operation failed without the step, the cause or the fix, and the baseline allows 0 of it in this file while it holds 1; observed: eprintln!("the push did not succeed");`),
    result.stdout,
  );
  assert.match(result.stdout, /1 source file\(s\), 1 generic sentence\(s\), 1 refused, 0 stale baseline entries/);
});

test('a_baseline_above_what_a_file_holds_is_refused', () => {
  const { file, result } = scan('stale', (path) => ({ [path]: { 'did not succeed': 3 } }));
  assert.equal(result.status, 1);
  assert.ok(result.stdout.includes(`the baseline allows 3 of "did not succeed" in the file while it holds 1, and a baseline only shrinks; observed: 1 held, 3 allowed\nfix: lower the entry for ${file} in `), result.stdout);
});
