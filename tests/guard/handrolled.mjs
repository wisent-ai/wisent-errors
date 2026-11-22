// Real test of `node ci/no-handrolled-envelope.mjs <path>...`, the guard a
// consuming repository runs over its own source (README, "node
// ci/no-handrolled-envelope.mjs ../probierz/agent"; docs/errors/lint.md,
// `wisent_errors.lint.handrolled`, "Started through: `node
// ci/no-handrolled-envelope.mjs`").
//
//   node --test tests/guard/handrolled.mjs
//
// Rule 4: the guard is this package's own command, the program a consumer
// runs on its checkout; it is started here as that process with
// process.execPath, on a consumer tree seeded in the case's directory, which
// is the input it reads and not a stand-in for another component. Nothing
// else is involved: the guard has no backend, service or store.
// Rule 7: one test, the guard's whole story: started with no path and with an
// option it lacks, named an absent tree, then a clean tree, a clean file and
// this package's own source passing with the count of files read, a
// consuming tree whose hand-built envelope is listed line by line, and a
// directory it may not list refused. After every step the case's files are
// read back byte for byte (the guard writes nothing, never touches a file it
// reports) and its home is read back empty.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/guard-handrolled-<pid>/home; the
// guard has no backend variable of its own and reads nothing but the paths
// it is named.
// Rule 9: every status and sentence below was copied from the guard run by
// hand with `env -i` over the same seeded tree; only the case's paths are
// interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const USAGE = 'node ci/no-handrolled-envelope.mjs <path> [<path>...]';
// The statuses the guard answered: nothing refused, a refusal, a refusal of how it was started.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;
const HAND_BUILT = 'export const report = { failure_point: point, error_code: code };';
const AFTERWORD =
  '\nEach needs a reason. Building an envelope here means the derived fields can be' +
  '\nwrong, so build it with wisent-errors instead. Three answers are legitimate and' +
  '\ncommon: an operator-visible log line whose format is already parsed, a field' +
  "\ndeclaration, and another API's own `error_code` -- Azure has one, and this guard" +
  '\ncannot tell it from ours. Read the line before believing the count.\n';

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

// Every file under `dir`, by its path below it, with what it holds.
const filesUnder = (dir) =>
  Object.fromEntries(
    readdirSync(dir, { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile())
      .map((entry) => [relative(dir, join(entry.parentPath, entry.name)), readFileSync(join(entry.parentPath, entry.name), 'utf8')]),
  );

// The three lines of a refusal of `operation`'s cause `id`.
const refusal = (operation, id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: ${operation}.${id}; ${PAGE}#${operation.replaceAll('.', '-')}-${id}\n`;

test('the_guard_lists_every_hand_built_envelope_and_refuses_a_tree_it_cannot_read', () => {
  const dir = join(root, 'target', 'real-tests', `guard-handrolled-${process.pid}`);
  const home = join(dir, 'home');
  const work = join(dir, 'work');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  const seeded = {
    'tree/failure.mjs': `${HAND_BUILT}\n`,
    'tree/clean.mjs': 'export const nothing = 1;\n',
    // A file of no source kind and a skipped directory are not read.
    'tree/notes.txt': `${HAND_BUILT}\n`,
    'tree/node_modules/vendored.mjs': `${HAND_BUILT}\n`,
    'clean/clean.mjs': 'export const nothing = 1;\n',
    'clean/main.rs': 'fn main() {}\n',
  };
  for (const [path, text] of Object.entries(seeded)) {
    mkdirSync(join(work, path, '..'), { recursive: true });
    writeFileSync(join(work, path), text);
  }
  const guard = (...words) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'no-handrolled-envelope.mjs'), ...words], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(filesUnder(work), seeded, `${step}: the tree is left as it was`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    assert.deepEqual(guard(), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.arguments',
        'operands-miscounted',
        'reading the operands of ci/no-handrolled-envelope.mjs: it takes at least one path and was given 0; observed: operands given: (none)',
        `name at least one path: ${USAGE}`,
      ),
    });
    untouched('no path');

    assert.deepEqual(guard('--all', 'tree'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.arguments',
        'option-unknown',
        'reading the options of ci/no-handrolled-envelope.mjs: --all is not one of its options, and nothing it does reads it; observed: the words given: --all tree',
        `drop --all or spell it as one of its options: ${USAGE}`,
      ),
    });
    untouched('an unknown option');

    assert.deepEqual(guard('gone'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.paths',
        'path-absent',
        `opening the tree gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${work} exists and holds 2 entries: clean, tree`,
        `name the tree as it exists; a relative path is read from ${work}`,
      ),
    });
    untouched('an absent tree');

    assert.deepEqual(guard('clean'), { status: EXIT_SUCCESS, stdout: 'no hand-built envelope in 2 source file(s) under clean\n', stderr: '' });
    untouched('a clean tree');
    assert.deepEqual(guard('clean/main.rs'), { status: EXIT_SUCCESS, stdout: 'no hand-built envelope in 1 source file(s) under clean/main.rs\n', stderr: '' });
    untouched('a clean file');

    // js/index.mjs builds envelopes with failure_point and error_code keys:
    // this package is where they belong, so none of its files is read.
    const own = join(root, 'js');
    assert.deepEqual(guard(own), { status: EXIT_SUCCESS, stdout: `no hand-built envelope in 0 source file(s) under ${own}\n`, stderr: '' });
    untouched("the package's own source");

    assert.deepEqual(guard('tree'), {
      status: EXIT_FAILURE,
      stdout:
        refusal(
          'wisent_errors.lint.handrolled',
          'envelope-key-written',
          'reading 2 source file(s) under tree for hand-built envelopes: 1 line(s) write failure_point or error_code outside the package, so their derived fields can drift from the catalogue; observed: 1 line(s) below',
          "build each envelope with wisent-errors; a log line already parsed, a field declaration or another API's own error_code is a reason to keep the line, and reading it decides which",
        ) +
        `  tree/failure.mjs:1  ${HAND_BUILT}\n` +
        AFTERWORD,
      stderr: '',
    });
    untouched('a hand-built envelope');

    const locked = join(work, 'tree', 'locked');
    mkdirSync(locked);
    chmodSync(locked, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const ran = guard('tree');
    chmodSync(locked, 0o700); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    rmSync(locked, { recursive: true });
    assert.deepEqual(ran, {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.paths',
        'path-unreadable',
        "reading a directory of the tree tree/locked: the operating system refused to list or read it, so what it holds was never looked at; observed: tree/locked is a directory, mode 0, owner uid " +
          `${process.getuid()}; the operating system answered EACCES: permission denied, scandir 'tree/locked'`,
        'let the user running the command read it (chmod u+rx tree/locked), or leave it out of the paths named',
      ),
    });
    untouched('a directory it may not list');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
