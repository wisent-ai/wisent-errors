// Real tests of the parts loader (`wisent_errors.catalogue.parts`), run in a
// copy of this repository under the ignored target/ whose catalogue/failures/
// each case breaks: a directory that cannot be listed, one with no part, a
// part that cannot be read, that is not JSON or not the shape of a part, an
// operation declared in two parts, and a use no part declares.
//
//   node --test tests/tools/parts.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');

function broken(name, breakParts) {
  const copy = join(root, 'target', 'real-tests', 'tools-parts', `${name}-${process.pid}`);
  rmSync(copy, { recursive: true, force: true });
  mkdirSync(copy, { recursive: true });
  for (const part of ['catalogue', 'codegen', 'ci', 'js']) cpSync(join(root, part), join(copy, part), { recursive: true });
  const failures = join(copy, 'catalogue', 'failures');
  breakParts(failures);
  try {
    return spawnSync(process.execPath, [join(copy, 'ci', 'error-standard.mjs'), 'errors'], { encoding: 'utf8' });
  } finally {
    chmodSync(failures, 0o700);
    for (const file of ['envelope.json', 'tools.json']) if (existsSync(join(failures, file))) chmodSync(join(failures, file), 0o600);
    rmSync(copy, { recursive: true, force: true });
  }
}

const edit = (failures, file, change) => writeFileSync(join(failures, file), change(readFileSync(join(failures, file), 'utf8')));

test('an_unlisted_parts_directory_is_refused', () => {
  const result = broken('unlisted', (failures) => chmodSync(failures, 0o000));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /^Error: listing the failure catalogue parts in .*failures: the directory cannot be listed, so no part of the catalogue can be read; observed: .*mode 0.*EACCES/);
});

test('a_parts_directory_with_no_part_is_refused', () => {
  const result = broken('empty', (failures) => {
    for (const file of ['cli-output.json', 'envelope.json', 'lint-commands.json', 'lint-layers.json', 'tools.json']) rmSync(join(failures, file));
    writeFileSync(join(failures, 'notes.txt'), 'nothing');
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /the directory holds no \.json part, so this package would declare none of its own failures; observed: it holds .*notes\.txt/);
});

test('an_unreadable_part_is_refused', () => {
  const result = broken('unreadable', (failures) => chmodSync(join(failures, 'envelope.json'), 0o000));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /reading the failure catalogue part .*envelope\.json: the part is listed but cannot be read; observed: .*mode 0/);
});

test('a_part_that_is_not_json_is_refused', () => {
  const result = broken('syntax', (failures) => edit(failures, 'envelope.json', (text) => text.slice(0, 40)));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /reading the failure catalogue part .*envelope\.json: the part is not JSON; observed: 40 bytes; the decoder answered /);
});

test('a_part_of_the_wrong_shape_is_refused', () => {
  const result = broken('shape', (failures) => edit(failures, 'envelope.json', (text) => text.replaceAll('"tests": {', '"checks": {')));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /the part is JSON but not an object with an area and a list of operations.*observed: at operations\[0\]\.causes\[0\]\.tests it holds nothing/);
});

test('an_operation_declared_in_two_parts_is_refused', () => {
  const result = broken('twice', (failures) => writeFileSync(join(failures, 'zz-copy.json'), readFileSync(join(failures, 'tools.json'))));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /the operation wisent_errors\.census\.implementations is declared in both .*tools\.json and .*zz-copy\.json/);
});

test('a_use_no_part_declares_is_refused', () => {
  const result = broken('use', (failures) => edit(failures, 'tools.json', (text) => text.replace('"uses": ["wisent_errors.lint.paths"]', '"uses": ["wisent_errors.lint.gone"]')));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /the operation wisent_errors\.census\.implementations uses wisent_errors\.lint\.gone, which no part declares/);
});
