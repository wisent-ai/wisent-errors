// Real test of `node codegen/generate.mjs [--check]`, the generator that
// writes the four runtimes' vocabulary, declaration rules and own failure
// catalogue from catalogue/, and with --check says which of them drifted
// (docs/errors/tools.md, `wisent_errors.codegen.generate`, "Started through:
// `node codegen/generate.mjs`, `node codegen/generate.mjs --check`"; the
// `checks` gate of .wisent-release.json runs --check through ci/check.mjs).
//
//   node --test tests/tools/generate.mjs
//
// Rule 4: the generator is this package's own command, started as the
// process its maintainer and the gate start, with process.execPath. It
// writes into the package it ships in, so it runs in a copy of the package
// (catalogue/, codegen/, ci/, js/, rust/, python/, swift/, docs/) under
// target/real-tests/tools-generate-<pid>/package, whose generated files each
// step edits, makes unwritable or unreadable, or adds to, the way a
// maintainer's checkout ends up; nothing in the copy stands in for another
// component and the generator has no backend. Its effect is the files it
// writes and removes, read back after every step.
// Rule 5: every step asserts the exit status and the whole of stdout (one
// line per generated file, in the generator's order) and stderr (a
// refusal's three lines), then reads the files back: --check leaves an
// edited file and a stale module as they are, generating writes the edited
// file back to what the catalogue says and removes the stale module, a
// refused write leaves the file as it was, and the case's home stays empty.
// Rule 7: one test, the generator's whole story: the intact copy checked,
// then a misspelt option and an operand refused, a hand-edited file refused
// by --check as drift and written back by generating, a module no part
// writes any more refused by --check as stale and removed by generating, and
// a file it may not write, a file it may not read and a module it may not
// remove, each refused. ci/check.mjs, which runs --check among its checks,
// is its own command and its own test (tests/ship/check.mjs).
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside the case's home; the generator has no backend
// variable of its own and reads only the package it runs from.
// Rule 9: every sentence below was copied from the generator run by hand
// with `env -i` over a copy changed the same way; only the copy's paths, the
// owner's uid and the size of the file the step wrote are interpolated. The
// list of generated files is the one the intact copy's --check prints, read
// back as the files the copy holds, because it grows with the catalogue. The
// first step expects the package's generated files to match its catalogue,
// as the `checks` gate requires before anything lands.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const TOOLS = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const LINT = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const USAGE = 'node codegen/generate.mjs [--check]';
// The statuses the generator answered: nothing refused, a refusal, a refusal of how it was started.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;
// What a build, a Python install or a cache leaves in a checkout is not the package.
const SCRATCH = new Set(['target', '.build', '__pycache__', 'wisent_errors.egg-info']);
const EDITED = 'js/catalogue/declaration.mjs';
// js/index.mjs imports the JS modules, so an unreadable one stops Node before the generator runs; this file only the generator reads.
const UNREADABLE = 'python/wisent_errors/declaration.py';
const STALE = 'swift/Sources/WisentErrors/Own/OwnFailuresRetired.swift';
const UNREMOVABLE = 'rust/src/failures/retired.rs';
const HAND = '// edited by hand\n';

// The child's whole environment: PATH, and a home, temporary directory and XDG directories inside the case.
const isolated = (home) => ({
  PATH: process.env.PATH,
  HOME: home,
  TMPDIR: home,
  XDG_CONFIG_HOME: join(home, '.config'),
  XDG_CACHE_HOME: join(home, '.cache'),
  XDG_DATA_HOME: join(home, '.local', 'share'),
  XDG_STATE_HOME: join(home, '.local', 'state'),
});

// The three lines of a refusal of `operation`'s cause `id`, listed on `page`.
const refusal = (page, operation, id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: ${operation}.${id}; ${page}#${operation.replaceAll('.', '-')}-${id}\n`;

// The --check refusal of the generated files `names` that differ.
const drifted = (names) =>
  refusal(
    TOOLS,
    'wisent_errors.codegen.generate',
    'generated-drifted',
    `comparing the generated files with catalogue/: ${names.length} generated file(s) differ from what the catalogue writes, so the runtimes would not say what the catalogue declares; observed: ${names.join(', ')}`,
    'run `node codegen/generate.mjs` and commit what it writes',
  );

test('generate_writes_what_the_catalogue_says_and_check_refuses_every_drift', () => {
  const dir = join(root, 'target', 'real-tests', `tools-generate-${process.pid}`);
  const home = join(dir, 'home');
  const copy = join(dir, 'package');
  const uid = process.getuid();
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  for (const part of ['catalogue', 'codegen', 'ci', 'js', 'rust', 'python', 'swift', 'docs']) {
    cpSync(join(root, part), join(copy, part), { recursive: true, filter: (path) => !SCRATCH.has(basename(path)) });
  }
  const generate = (...words) => {
    const ran = spawnSync(process.execPath, [join(copy, 'codegen', 'generate.mjs'), ...words], { cwd: dir, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const at = (name) => join(copy, name);
  const read = (name) => readFileSync(at(name), 'utf8');
  const homeEmpty = (step) => assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  try {
    // The intact copy: every generated file unchanged; their names, in the generator's order, are the lines every later step prints.
    const intact = generate('--check');
    assert.equal(intact.status, EXIT_SUCCESS, intact.stdout + intact.stderr);
    assert.equal(intact.stderr, '');
    const names = intact.stdout.trimEnd().split('\n').map((line) => {
      assert.match(line, /^unchanged {2}\S+$/);
      return line.slice('unchanged  '.length);
    });
    for (const name of [EDITED, UNREADABLE, 'rust/src/codes.rs', 'docs/errors/tools.md']) assert.ok(names.includes(name), `${name} is generated`);
    for (const name of names) assert.ok(existsSync(at(name)), `${name} is a file of the copy`);
    const generated = Object.fromEntries(names.map((name) => [name, read(name)]));
    // fallback: a file the step did not touch is printed `unchanged`, as the intact copy printed it.
    const lines = (from, to, replaced = {}) => names.slice(from, to).map((name) => `${replaced[name] ?? 'unchanged '} ${name}\n`).join('');
    // After a step: every generated file holds what the catalogue writes, but for `changed`.
    const holds = (step, changed = {}) => {
      // fallback: a file the step did not change holds what the intact copy held.
      for (const name of names) assert.equal(read(name), changed[name] ?? generated[name], `${step}: ${name}`);
      homeEmpty(step);
    };
    holds('the intact copy');

    assert.deepEqual(generate('--chek'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.arguments',
        'option-unknown',
        'reading the options of codegen/generate.mjs: --chek is not one of its options, and nothing it does reads it; observed: the words given: --chek',
        `drop --chek or spell it as one of its options: ${USAGE}`,
      ),
    });
    holds('a misspelt --check');
    assert.deepEqual(generate('rust'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.arguments',
        'operands-miscounted',
        'reading the operands of codegen/generate.mjs: it takes no operand and was given 1; observed: operands given: rust',
        `name no operand: ${USAGE}`,
      ),
    });
    holds('an operand');

    const edited = generated[EDITED] + HAND;
    writeFileSync(at(EDITED), edited);
    assert.deepEqual(generate('--check'), { status: EXIT_FAILURE, stdout: lines(0, names.length, { [EDITED]: 'DRIFTED   ' }), stderr: drifted([EDITED]) });
    holds('a hand-edited file, checked', { [EDITED]: edited });
    assert.deepEqual(generate(), { status: EXIT_SUCCESS, stdout: lines(0, names.length, { [EDITED]: 'written   ' }), stderr: '' });
    holds('a hand-edited file, generated');

    writeFileSync(at(STALE), 'extension OwnFailures {}\n');
    assert.deepEqual(generate('--check'), { status: EXIT_FAILURE, stdout: `${lines(0, names.length)}STALE      ${STALE}\n`, stderr: drifted([STALE]) });
    holds('a module no part writes, checked');
    assert.equal(read(STALE), 'extension OwnFailures {}\n', '--check removes nothing');
    assert.deepEqual(generate(), { status: EXIT_SUCCESS, stdout: `${lines(0, names.length)}removed    ${STALE}\n`, stderr: '' });
    holds('a module no part writes, generated');
    assert.equal(existsSync(at(STALE)), false, 'the stale module is removed');

    writeFileSync(at(EDITED), edited);
    chmodSync(at(EDITED), 0o444); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unwritable = generate();
    chmodSync(at(EDITED), 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(unwritable, {
      status: EXIT_FAILURE,
      stdout: lines(0, names.indexOf(EDITED)),
      stderr: refusal(
        TOOLS,
        'wisent_errors.codegen.generate',
        'generated-unwritable',
        `writing the generated ${EDITED}: the operating system refused to create or write the file, so the runtime keeps what an older catalogue wrote; observed: ${at(EDITED)} is a file of ${Buffer.byteLength(edited)} bytes, mode 444, owner uid ${uid}; the operating system answered EACCES: permission denied, open '${at(EDITED)}'`,
        `let the user running the generator write ${at(EDITED)} and its directory, then generate again`,
      ),
    });
    holds('a file it may not write', { [EDITED]: edited });
    writeFileSync(at(EDITED), generated[EDITED]);

    chmodSync(at(UNREADABLE), 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unreadable = generate();
    chmodSync(at(UNREADABLE), 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(unreadable, {
      status: EXIT_FAILURE,
      stdout: lines(0, names.indexOf(UNREADABLE)),
      stderr: refusal(
        LINT,
        'wisent_errors.lint.input',
        'input-not-permitted',
        `reading the generated file ${at(UNREADABLE)}: the file exists but its permissions refuse this process the read; observed: ${at(UNREADABLE)} is a file of ${Buffer.byteLength(generated[UNREADABLE])} bytes, mode 0, owner uid ${uid}; the operating system answered EACCES: permission denied, open '${at(UNREADABLE)}'`,
        `let the user running the command read it (chmod u+r ${at(UNREADABLE)}), or run the command as its owner`,
      ),
    });
    holds('a file it may not read, never overwritten');

    const failures = dirname(at(UNREMOVABLE));
    writeFileSync(at(UNREMOVABLE), '//! retired\n');
    chmodSync(failures, 0o555); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unremovable = generate();
    chmodSync(failures, 0o755); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(unremovable, {
      status: EXIT_FAILURE,
      stdout: lines(0, names.length),
      stderr: refusal(
        TOOLS,
        'wisent_errors.codegen.generate',
        'generated-unremovable',
        `removing the generated ${UNREMOVABLE}, which no part of catalogue/failures/ writes any more: the operating system refused to remove the file, so the runtime still holds a declaration the catalogue no longer has; observed: ${at(UNREMOVABLE)} is a file of 12 bytes, mode 644, owner uid ${uid}; its directory: ${failures} is a directory, mode 555, owner uid ${uid}; the operating system answered EACCES: permission denied, unlink '${at(UNREMOVABLE)}'`,
        `let the user running the generator write ${failures}, or remove ${at(UNREMOVABLE)} yourself, then generate again`,
      ),
    });
    holds('a module it may not remove');
    assert.equal(read(UNREMOVABLE), '//! retired\n', 'the refused module is still there');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
