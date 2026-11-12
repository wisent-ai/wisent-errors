// Real test of `node ci/no-handrolled-envelope.mjs`: a consuming tree that
// writes an envelope key by hand is listed line by line, and a clean tree
// says how many files it read.
//
//   node --test tests/lint/handrolled.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');

test('a_hand_built_envelope_is_listed', () => {
  const dir = join(root, 'target', 'real-tests', 'lint-handrolled', `${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  try {
    writeFileSync(join(dir, 'failure.mjs'), "export const report = { failure_point: point, error_code: code };\n");
    writeFileSync(join(dir, 'clean.mjs'), 'export const nothing = 1;\n');
    const result = spawnSync(process.execPath, [join(root, 'ci', 'no-handrolled-envelope.mjs'), dir], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stdout, /^Error: reading 2 source file\(s\) under .* for hand-built envelopes: 1 line\(s\) write failure_point or error_code outside the package/);
    assert.match(result.stdout, /\n {2}.*failure\.mjs:1 {2}export const report = \{ failure_point: point, error_code: code \};/);
    rmSync(join(dir, 'failure.mjs'));
    const clean = spawnSync(process.execPath, [join(root, 'ci', 'no-handrolled-envelope.mjs'), dir], { encoding: 'utf8' });
    assert.equal(clean.status, 0);
    assert.match(clean.stdout, /^no hand-built envelope in 1 source file\(s\) under /);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
