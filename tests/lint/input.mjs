// Real test of how `node ci/error-standard.mjs catalogue <listing>` reads the
// one file it is named, through the declared layer `wisent_errors.lint.input`
// (docs/errors/lint.md; every command of this package reads a JSON or text
// file it is named through it). `catalogue` is the command a consuming
// repository runs on the listing its own `errors list --json` printed
// (README, "The lint a product runs"; docs/errors/lint.md, "Started through:
// `node ci/error-standard.mjs catalogue`").
//
//   node --test tests/lint/input.mjs
//
// Rule 4: `catalogue` is this package's own command, run here as the process
// a consumer starts, with process.execPath, in a consumer's directory seeded
// in the case; the listing file written there is the input the command
// reads, as a product's `errors list --json` leaves it, not a stand-in for
// another component. The command has no backend to reach.
// Rule 7: one test, `catalogue`'s story of the file it is named: absent, a
// directory, a file it may not read, then a listing read (a list and an
// object with operations), then a file cut short, a file whose decoder stops
// at an unexpected token on its third line, and JSON of another shape, each
// refused. What the command does with a listing it has read is
// tests/lint/catalogue.mjs.
// Rule 5: each step asserts the exit status and the whole of stdout and
// stderr, then reads the case's files back byte for byte (the refused input
// is left as it was, nothing is created beside it) and its home back empty.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/lint-input-<pid>/home; the
// command has no backend variable of its own and reads only the file named.
// Rule 9: every status and sentence below was copied from the command run by
// hand with `env -i` over the same seeded files; only the case's paths and
// the owner's uid are interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const EXPECTED = 'a list of functionalities, or an object with operations';
const EMPTY = '0 functionalities, 0 with a complete catalogue, 0 refused; 0 entries starting no declared functionality\n';
// The statuses the command answered: nothing refused, a refusal, a refusal of what it was named.
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
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.input.${id}; ${PAGE}#wisent_errors-lint-input-${id}\n`,
});

test('the_catalogue_command_reads_the_listing_it_is_named_or_refuses_it_by_what_is_there', () => {
  const dir = join(root, 'target', 'real-tests', `lint-input-${process.pid}`);
  const home = join(dir, 'home');
  const work = join(dir, 'work');
  const listing = join(work, 'errors.json');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  mkdirSync(join(work, 'listings'), { recursive: true });
  chmodSync(join(work, 'listings'), 0o755); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
  const uid = process.getuid();
  const catalogue = (path) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'catalogue', path], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const holds = (step, files) => {
    assert.deepEqual(filesUnder(work), files, `${step}: the directory holds what was written, and nothing more`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    assert.deepEqual(
      catalogue('errors.json'),
      refused(
        USAGE_EXIT,
        'input-absent',
        `reading the catalogue errors.json: no file is at that path; observed: ${work} exists and holds 1 entry: listings`,
        `name the file that holds the catalogue, or write it first; a relative path is read from ${work}`,
      ),
    );
    holds('an absent listing', {});

    assert.deepEqual(
      catalogue('listings'),
      refused(
        USAGE_EXIT,
        'input-is-directory',
        `reading the catalogue listings: the path names a directory, and the catalogue is one file; observed: listings is a directory, mode 755, owner uid ${uid}`,
        'name the JSON file inside it, not the directory',
      ),
    );
    holds('a directory', {});

    writeFileSync(listing, '[]');
    chmodSync(listing, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unreadable = catalogue('errors.json');
    chmodSync(listing, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(
      unreadable,
      refused(
        EXIT_FAILURE,
        'input-not-permitted',
        `reading the catalogue errors.json: the file exists but its permissions refuse this process the read; observed: errors.json is a file of 2 bytes, mode 0, owner uid ${uid}; the operating system answered EACCES: permission denied, open 'errors.json'`,
        'let the user running the command read it (chmod u+r errors.json), or run the command as its owner',
      ),
    );
    holds('a listing it may not read', { 'errors.json': '[]' });

    assert.deepEqual(catalogue('errors.json'), { status: EXIT_SUCCESS, stdout: EMPTY, stderr: '' });
    holds('a list read', { 'errors.json': '[]' });
    writeFileSync(listing, '{"operations": []}');
    assert.deepEqual(catalogue('errors.json'), { status: EXIT_SUCCESS, stdout: EMPTY, stderr: '' });
    holds('an object with operations read', { 'errors.json': '{"operations": []}' });

    const cut = '[{"operation": ';
    writeFileSync(listing, cut);
    assert.deepEqual(
      catalogue('errors.json'),
      refused(
        EXIT_FAILURE,
        'input-not-json',
        'reading the catalogue errors.json: the file is not JSON; observed: 15 bytes, starting "[{\\"operation\\": "; the decoder answered Unexpected end of JSON input, stopping at line 1, column 16: "[{\\"operation\\": "',
        `write the catalogue as JSON (${EXPECTED}), correcting errors.json at line 1, column 16: "[{\\"operation\\": "`,
      ),
    );
    holds('a listing cut short', { 'errors.json': cut });

    // V8 names no position for an unexpected token, only the text around it,
    // line breaks and all; the refusal says the line and column and keeps to
    // its three lines.
    const token = '[\n  {"operation": "example.engine.check",\n   "entries": [}\n]\n';
    writeFileSync(listing, token);
    assert.deepEqual(
      catalogue('errors.json'),
      refused(
        EXIT_FAILURE,
        'input-not-json',
        'reading the catalogue errors.json: the file is not JSON; observed: 61 bytes, starting "["; the decoder answered Unexpected token \'}\', ..."ntries": [}\\n]\\n" is not valid JSON, stopping at line 3, column 16: "   \\"entries\\": [}"',
        `write the catalogue as JSON (${EXPECTED}), correcting errors.json at line 3, column 16: "   \\"entries\\": [}"`,
      ),
    );
    holds('a listing with an unexpected token', { 'errors.json': token });

    writeFileSync(listing, '{"functionalities": []}');
    assert.deepEqual(
      catalogue('errors.json'),
      refused(
        EXIT_FAILURE,
        'input-wrong-shape',
        `reading the catalogue errors.json: the file is JSON but not ${EXPECTED}; observed: it holds an object with functionalities`,
        `write the catalogue as ${EXPECTED}`,
      ),
    );
    holds('JSON of another shape', { 'errors.json': '{"functionalities": []}' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
