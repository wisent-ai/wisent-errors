// Real tests of `node codegen/generate.mjs` and `node ci/check.mjs`, run in a
// copy of this repository under the ignored target/ so a broken manifest, a
// drifted, stale or unwritable generated file, or a schema naming other codes
// never touches the checkout: a drifted file, a module no part writes any
// more, an unwritable file, an unremovable one, and a schema naming other codes.
//
//   node --test tests/tools/generate.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, chmodSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PARTS = ['catalogue', 'codegen', 'ci', 'js', 'rust', 'python', 'swift', 'schema', 'docs', 'tests'];

function inCopy(name, body) {
  const copy = join(root, 'target', 'real-tests', 'tools-generate', `${name}-${process.pid}`);
  rmSync(copy, { recursive: true, force: true });
  mkdirSync(copy, { recursive: true });
  for (const part of PARTS) cpSync(join(root, part), join(copy, part), { recursive: true, filter: (path) => !path.includes('/target') && !path.includes('__pycache__') });
  try {
    return body(copy, (script, words = [], env = process.env) => spawnSync(process.execPath, [join(copy, script), ...words], { encoding: 'utf8', env }));
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
}

test('a_drifted_generated_file_is_refused', () => {
  inCopy('drift', (copy, run) => {
    appendFileSync(join(copy, 'js', 'declaration.mjs'), '// edited by hand\n');
    const result = run('codegen/generate.mjs', ['--check']);
    assert.equal(result.status, 1);
    assert.match(result.stdout, /DRIFTED {4}js\/declaration\.mjs/);
    assert.match(result.stderr, /generated file\(s\) differ from what the catalogue writes.*observed: .*js\/declaration\.mjs/);
  });
});

test('an_unwritable_generated_file_is_refused', () => {
  inCopy('unwritable', (copy, run) => {
    const target = join(copy, 'js', 'declaration.mjs');
    appendFileSync(target, '// edited by hand\n');
    chmodSync(target, 0o444);
    const result = run('codegen/generate.mjs');
    chmodSync(target, 0o644);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /writing the generated js\/declaration\.mjs: the operating system refused to create or write the file, so the runtime keeps what an older catalogue wrote; observed: .*mode 444/);
  });
});

test('a_stale_generated_module_is_drift_and_generating_removes_it', () => {
  inCopy('stale', (copy, run) => {
    const retired = join(copy, 'swift', 'Sources', 'WisentErrors', 'OwnFailuresRetired.swift');
    writeFileSync(retired, 'extension OwnFailures {}\n');
    const checked = run('codegen/generate.mjs', ['--check']);
    assert.equal(checked.status, 1);
    assert.match(checked.stdout, /STALE {6}swift\/Sources\/WisentErrors\/OwnFailuresRetired\.swift/);
    const generated = run('codegen/generate.mjs');
    assert.equal(generated.status, 0, generated.stderr);
    assert.equal(existsSync(retired), false);
  });
});

test('an_unremovable_stale_module_is_refused', () => {
  inCopy('unremovable', (copy, run) => {
    const directory = join(copy, 'rust', 'src', 'failures');
    writeFileSync(join(directory, 'retired.rs'), '//! retired\n');
    chmodSync(directory, 0o555);
    const result = run('codegen/generate.mjs');
    chmodSync(directory, 0o755);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /removing the generated rust\/src\/failures\/retired\.rs, which no part of catalogue\/failures\/ writes any more: the operating system refused to remove the file.*its directory: .*mode 555/);
  });
});

test('a_schema_naming_other_codes_is_refused', () => {
  inCopy('schema', (copy, run) => {
    const schema = join(copy, 'schema', 'failure.schema.json');
    const document = JSON.parse(readFileSync(schema, 'utf8'));
    document.properties.error_code.enum.push('offline');
    writeFileSync(schema, JSON.stringify(document, null, 2));
    const result = run('ci/check.mjs');
    assert.equal(result.status, 1);
    assert.match(result.stdout, /FAIL {2}schema and catalogue name the same codes\n {8}Error: comparing the codes of schema\/failure\.schema\.json with catalogue\/codes\.json: the schema names other codes than the catalogue.*schema config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown, offline/);
  });
});
