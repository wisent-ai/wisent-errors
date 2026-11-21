// Real tests of `node codegen/generate.mjs` and `node ci/check.mjs`, run in a
// copy of this repository under the ignored target/ so a broken manifest, a
// drifted, stale or unwritable generated file, or a schema naming other codes
// never touches the checkout: generating writes back a drifted file, a
// drifted file and a module no part writes any more are refused by --check,
// an unwritable file and an unremovable one are refused, and a schema naming
// other codes is refused. Each refusal is the whole of stderr; what the
// operating system answers is read by asking it the same way, and what each
// file holds afterwards is read from the copy.
//
//   node --test tests/tools/generate.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, chmodSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';

const root = resolve(import.meta.dirname, '../..');
const PARTS = ['catalogue', 'codegen', 'ci', 'js', 'rust', 'python', 'swift', 'schema', 'docs', 'tests'];
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const EDITED = 'js/catalogue/declaration.mjs';
// The generator loads js/index.mjs, which imports js/catalogue/declaration.mjs,
// so an unreadable JS module stops Node before the generator runs; the
// unreadable case takes a generated file only the generator reads.
const UNREADABLE = 'python/wisent_errors/declaration.py';

function inCopy(name, body) {
  const copy = join(root, 'target', 'real-tests', 'tools-generate', `${name}-${process.pid}`);
  rmSync(copy, { recursive: true, force: true });
  mkdirSync(copy, { recursive: true });
  for (const part of PARTS) cpSync(join(root, part), join(copy, part), { recursive: true, filter: (path) => !path.includes('/target') && !path.includes('__pycache__') });
  try {
    return body(copy, (script, words = []) => {
      const ran = spawnSync(process.execPath, [join(copy, script), ...words], { encoding: 'utf8' });
      return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
    });
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
}

// The three lines of a refusal of the generator's cause `id`.
const refusal = (id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.codegen.generate.${id}; ${PAGE}#wisent_errors-codegen-generate-${id}\n`;

// The lines of a generator's stdout that are not `unchanged  <name>` of an existing file.
const changed = (copy, stdout) =>
  stdout.split('\n').filter((line) => line !== '' && !(line.startsWith('unchanged  ') && existsSync(join(copy, line.slice('unchanged  '.length)))));

// What `path` is, as the generator's refusals say it.
function state(path) {
  const entry = statSync(path);
  return `${path} is ${entry.isDirectory() ? 'a directory' : `a file of ${entry.size} bytes`}, mode ${(entry.mode & 0o777).toString(8)}, owner uid ${entry.uid}`;
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

const driftedRefusal = (names) =>
  refusal(
    'generated-drifted',
    `comparing the generated files with catalogue/: ${names.length} generated file(s) differ from what the catalogue writes, so the runtimes would not say what the catalogue declares; observed: ${names.join(', ')}`,
    'run `node codegen/generate.mjs` and commit what it writes',
  );

test('a_drifted_generated_file_is_refused', () => {
  inCopy('drift', (copy, run) => {
    const target = join(copy, EDITED);
    appendFileSync(target, '// edited by hand\n');
    const edited = readFileSync(target, 'utf8');
    const checked = run('codegen/generate.mjs', ['--check']);
    assert.equal(checked.status, EXIT_FAILURE);
    assert.deepEqual(changed(copy, checked.stdout), [`DRIFTED    ${EDITED}`]);
    assert.equal(checked.stderr, driftedRefusal([EDITED]));
    assert.equal(readFileSync(target, 'utf8'), edited, '--check writes nothing');
  });
});

test('generating_writes_back_what_the_catalogue_says', () => {
  inCopy('generate', (copy, run) => {
    const target = join(copy, EDITED);
    appendFileSync(target, '// edited by hand\n');
    const generated = run('codegen/generate.mjs');
    assert.equal(generated.status, EXIT_SUCCESS, generated.stderr);
    assert.equal(generated.stderr, '');
    assert.deepEqual(changed(copy, generated.stdout), [`written    ${EDITED}`]);
    assert.equal(readFileSync(target, 'utf8').includes('// edited by hand'), false, 'the hand edit is gone');
    const checked = run('codegen/generate.mjs', ['--check']);
    assert.deepEqual({ status: checked.status, changed: changed(copy, checked.stdout), stderr: checked.stderr }, { status: EXIT_SUCCESS, changed: [], stderr: '' });
  });
});

test('an_unwritable_generated_file_is_refused', () => {
  inCopy('unwritable', (copy, run) => {
    const target = join(copy, EDITED);
    appendFileSync(target, '// edited by hand\n');
    const edited = readFileSync(target, 'utf8');
    chmodSync(target, 0o444); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const result = run('codegen/generate.mjs');
    const observed = `${state(target)}; the operating system answered ${answered(() => writeFileSync(target, edited))}`;
    chmodSync(target, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.equal(result.status, EXIT_FAILURE);
    assert.deepEqual(changed(copy, result.stdout), [], 'nothing was written before the refusal');
    assert.equal(
      result.stderr,
      refusal(
        'generated-unwritable',
        `writing the generated ${EDITED}: the operating system refused to create or write the file, so the runtime keeps what an older catalogue wrote; observed: ${observed}`,
        `let the user running the generator write ${target} and its directory, then generate again`,
      ),
    );
    assert.equal(readFileSync(target, 'utf8'), edited, 'the refused file keeps what it held');
  });
});

test('an_unreadable_generated_file_is_refused_before_it_is_overwritten', () => {
  inCopy('unreadable', (copy, run) => {
    const target = join(copy, UNREADABLE);
    const held = readFileSync(target, 'utf8');
    chmodSync(target, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const result = run('codegen/generate.mjs');
    const observed = `${state(target)}; the operating system answered ${answered(() => readFileSync(target, 'utf8'))}`;
    chmodSync(target, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.equal(result.status, EXIT_FAILURE);
    assert.deepEqual(changed(copy, result.stdout), [], 'nothing was written before the refusal');
    assert.equal(
      result.stderr,
      `Error: reading the generated file ${target}: the file exists but its permissions refuse this process the read; observed: ${observed}\n` +
        `fix: let the user running the command read it (chmod u+r ${target}), or run the command as its owner\n` +
        'cause: wisent_errors.lint.input.input-not-permitted; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md#wisent_errors-lint-input-input-not-permitted\n',
    );
    assert.equal(readFileSync(target, 'utf8'), held, 'the refused file is not overwritten');
  });
});

test('a_stale_generated_module_is_drift_and_generating_removes_it', () => {
  inCopy('stale', (copy, run) => {
    const name = 'swift/Sources/WisentErrors/Own/OwnFailuresRetired.swift';
    const retired = join(copy, name);
    writeFileSync(retired, 'extension OwnFailures {}\n');
    const checked = run('codegen/generate.mjs', ['--check']);
    assert.equal(checked.status, EXIT_FAILURE);
    assert.deepEqual(changed(copy, checked.stdout), [`STALE      ${name}`]);
    assert.equal(checked.stderr, driftedRefusal([name]));
    assert.equal(existsSync(retired), true, '--check removes nothing');
    const generated = run('codegen/generate.mjs');
    assert.equal(generated.status, EXIT_SUCCESS, generated.stderr);
    assert.deepEqual(changed(copy, generated.stdout), [`removed    ${name}`]);
    assert.equal(existsSync(retired), false);
  });
});

test('an_unremovable_stale_module_is_refused', () => {
  inCopy('unremovable', (copy, run) => {
    const name = 'rust/src/failures/retired.rs';
    const directory = join(copy, 'rust', 'src', 'failures');
    const retired = join(copy, name);
    writeFileSync(retired, '//! retired\n');
    chmodSync(directory, 0o555); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const result = run('codegen/generate.mjs');
    const observed = `${state(retired)}; its directory: ${state(directory)}; the operating system answered ${answered(() => unlinkSync(retired))}`;
    chmodSync(directory, 0o755); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.equal(result.status, EXIT_FAILURE);
    assert.deepEqual(changed(copy, result.stdout), []);
    assert.equal(
      result.stderr,
      refusal(
        'generated-unremovable',
        `removing the generated ${name}, which no part of catalogue/failures/ writes any more: the operating system refused to remove the file, so the runtime still holds a declaration the catalogue no longer has; observed: ${observed}`,
        `let the user running the generator write ${directory}, or remove ${retired} yourself, then generate again`,
      ),
    );
    assert.equal(existsSync(retired), true, 'the refused module is still there');
  });
});

test('a_schema_naming_other_codes_is_refused', () => {
  inCopy('schema', (copy, run) => {
    const schema = join(copy, 'schema', 'failure.schema.json');
    const document = JSON.parse(readFileSync(schema, 'utf8'));
    document.properties.error_code.enum.push('offline');
    writeFileSync(schema, JSON.stringify(document, null, 2));
    const result = run('ci/check.mjs');
    assert.equal(result.status, EXIT_FAILURE);
    const codes = 'config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown';
    const block =
      'FAIL  schema and catalogue name the same codes\n' +
      `        Error: comparing the codes of schema/failure.schema.json with catalogue/codes.json: the schema names other codes than the catalogue, so a checked envelope and a generated runtime disagree; observed: catalogue ${codes}; schema ${codes}, offline\n` +
      '        fix: change schema/failure.schema.json to name what catalogue/codes.json names\n' +
      `        cause: wisent_errors.ship.check.vocabulary-differs; ${PAGE}#wisent_errors-ship-check-vocabulary-differs\n`;
    assert.ok(result.stdout.includes(block), result.stdout);
    assert.ok(result.stdout.startsWith('ok    generated code matches the catalogue\n'), result.stdout);
    assert.ok(result.stdout.includes('\nok    schema and catalogue name the same severities\nok    the failure point pattern is stated once\n'), result.stdout);
    assert.match(result.stdout, /\n\d+ check\(s\) failed: schema and catalogue name the same codes(; [^\n]+)?\n$/);
  });
});
