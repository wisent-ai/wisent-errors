// Real tests of the parts loader (`wisent_errors.catalogue.parts`), run in a
// copy of this repository under the ignored target/ whose catalogue/failures/
// each case changes: a part in a subfolder read with the rest, a directory or
// a subfolder that cannot be listed, one with no part at any depth, a part
// that cannot be read, that is not JSON or not the shape of a part, an
// operation declared in two parts, and a use no part declares. Each run's
// whole stdout and stderr are compared, a refusal's three lines in full; what
// the operating system and JSON.parse say is read by asking them the same
// way, and the state observed (a mode, an owner, a listing) is read from the
// copy.
//
//   node --test tests/tools/parts.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';

// `node ci/error-standard.mjs errors` in a copy whose catalogue/failures/
// `breakParts` broke, and what `expected` says it must print, read from the
// copy before it is removed.
function broken(name, breakParts, expected) {
  const copy = join(root, 'target', 'real-tests', 'tools-parts', `${name}-${process.pid}`);
  rmSync(copy, { recursive: true, force: true });
  mkdirSync(copy, { recursive: true });
  for (const part of ['catalogue', 'codegen', 'ci', 'js']) cpSync(join(root, part), join(copy, part), { recursive: true });
  const failures = join(copy, 'catalogue', 'failures');
  breakParts(failures);
  try {
    const ran = spawnSync(process.execPath, [join(copy, 'ci', 'error-standard.mjs'), 'errors'], { encoding: 'utf8' });
    return { ran: { status: ran.status, stdout: ran.stdout, stderr: ran.stderr }, expected: expected(failures) };
  } finally {
    for (const folder of [failures, join(failures, 'lint')]) if (existsSync(folder)) chmodSync(folder, 0o700); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    for (const file of ['envelope.json', 'tools.json']) if (existsSync(join(failures, file))) chmodSync(join(failures, file), 0o600); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    rmSync(copy, { recursive: true, force: true });
  }
}

const edit = (failures, file, change) => writeFileSync(join(failures, file), change(readFileSync(join(failures, file), 'utf8')));

// Every part under `failures` at any depth, as its path below it, in the order the loader reads them.
const partFiles = (failures) => readdirSync(failures, { recursive: true }).filter((name) => name.endsWith('.json')).sort();

// The lines `errors` prints for the parts under `failures`: the loader's own
// functionality first, then every part's operations run in node, in path
// order, each with the causes tested in JavaScript.
function listing(failures) {
  const lines = ['wisent_errors.catalogue.parts: parts-unlisted, parts-absent, part-unreadable, part-not-json, part-wrong-shape, operation-declared-twice, uses-undeclared, raised-undeclared\n'];
  for (const file of partFiles(failures)) {
    for (const operation of JSON.parse(readFileSync(join(failures, file), 'utf8')).operations) {
      if (!operation.runtimes.includes('node')) continue;
      const causes = operation.causes.filter((cause) => cause.tests.js !== undefined).map((cause) => cause.id);
      lines.push(`${operation.id}: ${causes.join(', ') || `uses ${operation.uses.join(', ')}`}\n`);
    }
  }
  return lines.join('');
}

// What the operating system answers `attempt` with.
function answered(attempt) {
  try {
    attempt();
  } catch (error) {
    return error.message;
  }
  throw new Error('the attempt was to fail');
}

// `path` as stat reads it: a directory or a file, its permission bits and its owner.
function state(path) {
  const entry = statSync(path);
  return `${path} is a ${entry.isDirectory() ? 'directory' : 'file'} of mode ${(entry.mode & 0o777).toString(8)}, owner uid ${entry.uid}`;
}

// The whole of stderr for the loader's cause `id`.
const refusal = (id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.catalogue.parts.${id}; ${PAGE}#wisent_errors-catalogue-parts-${id}\n`;

const refused = (stderr) => ({ status: EXIT_FAILURE, stdout: '', stderr });

test('a_part_in_a_subfolder_is_read', () => {
  const { ran, expected } = broken('nested', (failures) => {
    mkdirSync(join(failures, 'more', 'deeper'), { recursive: true });
    renameSync(join(failures, 'tools.json'), join(failures, 'more', 'deeper', 'tools.json'));
  }, (failures) => {
    assert.ok(partFiles(failures).includes('more/deeper/tools.json'), partFiles(failures).join(', '));
    return listing(failures);
  });
  assert.match(expected, /^wisent_errors\.census\.implementations: /m, 'the moved part declares the census');
  assert.deepEqual(ran, { status: EXIT_SUCCESS, stdout: expected, stderr: '' });
});

test('an_unlisted_parts_directory_is_refused', () => {
  const { ran, expected } = broken('unlisted', (failures) => chmodSync(failures, 0o000), (failures) => refusal(
    'parts-unlisted',
    `listing the failure catalogue parts in ${failures}: the directory cannot be listed, so no part of the catalogue can be read; observed: ${state(failures)}; the operating system answered ${answered(() => readdirSync(failures))}`,
    'restore it with `git checkout -- catalogue/failures`, or let the user running the command read it',
  )); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
  assert.deepEqual(ran, refused(expected));
});

test('an_unlisted_parts_subfolder_is_refused', () => {
  const { ran, expected } = broken('unlisted-subfolder', (failures) => chmodSync(join(failures, 'lint'), 0o000), (failures) => {
    const folder = join(failures, 'lint');
    return refusal(
      'parts-unlisted',
      `listing the failure catalogue parts in ${folder}: the directory cannot be listed, so no part of the catalogue can be read; observed: ${state(folder)}; the operating system answered ${answered(() => readdirSync(folder))}`,
      'restore it with `git checkout -- catalogue/failures`, or let the user running the command read it',
    );
  }); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
  assert.deepEqual(ran, refused(expected));
});

test('a_parts_directory_with_no_part_is_refused', () => {
  // Every part at any depth goes; the emptied lint/ subfolder stays, so a
  // folder that holds no part is not taken for one.
  const { ran, expected } = broken('empty', (failures) => {
    for (const file of partFiles(failures)) rmSync(join(failures, file));
    writeFileSync(join(failures, 'notes.txt'), 'nothing');
  }, (failures) => {
    assert.ok(existsSync(join(failures, 'lint')), 'the lint/ subfolder is still there');
    return refusal(
      'parts-absent',
      `reading the failure catalogue parts in ${failures}: the directory holds no .json part, so this package would declare none of its own failures; observed: it holds ${readdirSync(failures).join(', ')}`,
      'restore the parts with `git checkout -- catalogue/failures`',
    );
  });
  assert.deepEqual(ran, refused(expected));
});

test('an_unreadable_part_is_refused', () => {
  const { ran, expected } = broken('unreadable', (failures) => chmodSync(join(failures, 'envelope.json'), 0o000), (failures) => {
    const path = join(failures, 'envelope.json');
    return refusal(
      'part-unreadable',
      `reading the failure catalogue part ${path}: the part is listed but cannot be read; observed: ${state(path)}; the operating system answered ${answered(() => readFileSync(path, 'utf8'))}`,
      `let the user running the command read it (chmod u+r ${path}), or restore it with \`git checkout -- ${path}\``,
    );
  }); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
  assert.deepEqual(ran, refused(expected));
});

test('a_part_that_is_not_json_is_refused', () => {
  const { ran, expected } = broken('syntax', (failures) => edit(failures, 'envelope.json', (text) => text.slice(0, 40)), (failures) => {
    const path = join(failures, 'envelope.json');
    const text = readFileSync(path, 'utf8');
    return refusal(
      'part-not-json',
      `reading the failure catalogue part ${path}: the part is not JSON; observed: ${Buffer.byteLength(text)} bytes; the decoder answered ${answered(() => JSON.parse(text))}`,
      `correct the JSON of ${path}; \`jq . ${path}\` points at the place it stops parsing`,
    );
  });
  assert.deepEqual(ran, refused(expected));
});

test('a_part_of_the_wrong_shape_is_refused', () => {
  const { ran, expected } = broken('shape', (failures) => edit(failures, 'envelope.json', (text) => text.replaceAll('"tests": {', '"checks": {')), (failures) => {
    const path = join(failures, 'envelope.json');
    return refusal(
      'part-wrong-shape',
      `reading the failure catalogue part ${path}: the part is JSON but not an object with an area and a list of operations, each with an id, runtimes, entries (one list, or one list per runtime) and causes carrying their tests; observed: at operations[0].causes[0].tests it holds nothing`,
      `write ${path} as an object with "area" and "operations", the way the other parts are written`,
    );
  });
  assert.deepEqual(ran, refused(expected));
});

test('an_operation_declared_in_two_parts_is_refused', () => {
  const { ran, expected } = broken('twice', (failures) => writeFileSync(join(failures, 'zz-copy.json'), readFileSync(join(failures, 'tools.json'))), (failures) => {
    const [first] = JSON.parse(readFileSync(join(failures, 'tools.json'), 'utf8')).operations;
    const parts = partFiles(failures).length;
    return refusal(
      'operation-declared-twice',
      `reading the failure catalogue parts in ${failures}: the operation ${first.id} is declared in both ${join(failures, 'tools.json')} and ${join(failures, 'zz-copy.json')}; observed: ${parts} part(s) read`,
      `keep ${first.id} in one part and delete it from the other`,
    );
  });
  assert.deepEqual(ran, refused(expected));
});

test('a_use_no_part_declares_is_refused', () => {
  // The census's uses list ends with lint.paths; an edit that matched nothing
  // would leave a valid catalogue and prove nothing, so it must change the part.
  const { ran, expected } = broken('use', (failures) => edit(failures, 'tools.json', (text) => {
    const changed = text.replace('"wisent_errors.lint.paths"]', '"wisent_errors.lint.gone"]');
    assert.notEqual(changed, text, 'tools.json names wisent_errors.lint.paths at the end of no uses list');
    return changed;
  }), (failures) => {
    // The operations the repository's own commands declare: the loader's own,
    // then every part's operations run in node, in path order.
    const declared = ['wisent_errors.catalogue.parts'];
    for (const name of partFiles(failures)) {
      for (const operation of JSON.parse(readFileSync(join(failures, name), 'utf8')).operations) {
        if (operation.runtimes.includes('node')) declared.push(operation.id);
      }
    }
    return refusal(
      'uses-undeclared',
      `joining the failure catalogue parts in ${failures}: the operation wisent_errors.census.implementations uses wisent_errors.lint.gone, which no part declares; observed: declared operations: ${declared.join(', ')}`,
      'declare wisent_errors.lint.gone in a part, or take it out of the uses of wisent_errors.census.implementations',
    );
  });
  assert.deepEqual(ran, refused(expected));
});
