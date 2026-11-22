// Real test of how `node ci/error-standard.mjs scan <dir>...` opens and walks
// the source directories it is named, through the declared layer
// `wisent_errors.lint.paths` (docs/errors/lint.md; every command of this
// package that reads a directory or walks a tree does it through it). `scan`
// is the command a consuming repository runs on its own source (README, "The
// lint a product runs"; docs/errors/lint.md, "Started through: `node
// ci/error-standard.mjs scan`"). Before this layer, an absent tree was
// reported clean.
//
//   node --test tests/lint/paths.mjs
//
// Rule 4: `scan` is this package's own command, run here as the process a
// consumer starts, with process.execPath, in a consumer's checkout seeded in
// the case; its source directory is the input the command reads, not a
// stand-in for another component. The command has no backend to reach.
// Rule 5: each step asserts the exit status and the whole of stdout and
// stderr, then reads the case's files back byte for byte (the command writes
// nothing and changes no mode) and its home back empty.
// Rule 7: one test, `scan`'s story of the directories it is named: a source
// directory walked and passed, then an absent one, a file named as one, a
// directory under it the command may not list and a source file it may not
// read, each refused. What `scan` holds the files it reads to is
// tests/lint/scan.mjs.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/lint-paths-<pid>/home; the
// command has no backend variable of its own.
// Rule 9: every status and sentence below was copied from `scan` run by hand
// with `env -i` over the same seeded checkout, not built from the
// catalogue's templates; only the case's paths and the owner's uid are
// interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
// The statuses `scan` answered: nothing refused, a refusal, a refusal of what it was named.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;

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

// The whole run of a refusal of the layer's cause `id`.
const refused = (status, id, sentence, remedy) => ({
  status,
  stdout: '',
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.paths.${id}; ${PAGE}#wisent_errors-lint-paths-${id}\n`,
});

test('scan_opens_the_source_directories_it_is_named_or_refuses_them', () => {
  const dir = join(root, 'target', 'real-tests', `lint-paths-${process.pid}`);
  const home = join(dir, 'home');
  const work = join(dir, 'work');
  const source = join(work, 'src', 'main.rs');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  mkdirSync(join(work, 'src'), { recursive: true });
  writeFileSync(source, 'fn main() {}\n');
  chmodSync(source, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
  const seeded = { 'src/main.rs': 'fn main() {}\n' };
  const uid = process.getuid();
  const scan = (...directories) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'scan', ...directories], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(filesUnder(work), seeded, `${step}: the checkout is left as it was`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    assert.deepEqual(scan('src'), { status: EXIT_SUCCESS, stdout: '1 source file(s), 0 generic sentence(s), 0 refused, 0 stale baseline entries\n', stderr: '' });
    untouched('a source directory');

    assert.deepEqual(
      scan('gone'),
      refused(
        USAGE_EXIT,
        'path-absent',
        `opening the source directory gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${work} exists and holds 1 entry: src`,
        `name the source directory as it exists; a relative path is read from ${work}`,
      ),
    );
    untouched('an absent directory');

    assert.deepEqual(
      scan('src/main.rs'),
      refused(
        USAGE_EXIT,
        'path-not-directory',
        `opening the source directory src/main.rs: the path is a file, and the source directory is read as a directory; observed: src/main.rs is a file of 13 bytes, mode 644, owner uid ${uid}`,
        `name the directory that holds it: ${join(work, 'src')}`,
      ),
    );
    untouched('a file named as a directory');

    const locked = join(work, 'src', 'locked');
    mkdirSync(locked);
    chmodSync(locked, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unlisted = scan('src');
    chmodSync(locked, 0o700); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    rmSync(locked, { recursive: true });
    assert.deepEqual(
      unlisted,
      refused(
        EXIT_FAILURE,
        'path-unreadable',
        `reading a source directory src/locked: the operating system refused to list or read it, so what it holds was never looked at; observed: src/locked is a directory, mode 0, owner uid ${uid}; the operating system answered EACCES: permission denied, scandir 'src/locked'`,
        'let the user running the command read it (chmod u+rx src/locked), or leave it out of the paths named',
      ),
    );
    untouched('a directory it may not list');

    chmodSync(source, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unread = scan('src');
    chmodSync(source, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(
      unread,
      refused(
        EXIT_FAILURE,
        'path-unreadable',
        `reading a source file src/main.rs: the operating system refused to list or read it, so what it holds was never looked at; observed: src/main.rs is a file of 13 bytes, mode 0, owner uid ${uid}; the operating system answered EACCES: permission denied, open 'src/main.rs'`,
        'let the user running the command read it (chmod u+rx src/main.rs), or leave it out of the paths named',
      ),
    );
    untouched('a source file it may not read');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
