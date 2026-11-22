// Real test of how `node ci/error-standard.mjs` reads the words it is started
// with, through the declared layer `wisent_errors.lint.arguments` (docs/errors/
// lint.md; every command of this package reads its words through it). The
// error standard is the command a consuming repository runs on its checkout
// (README, "The lint a product runs"; docs/errors/lint.md, "Started through:
// `node ci/error-standard.mjs scan`", "`node ci/error-standard.mjs
// catalogue`").
//
//   node --test tests/lint/arguments.mjs
//
// Rule 4: the error standard is this package's own command, run here as the
// process a consumer starts, with process.execPath, from a consumer's
// directory seeded in the case with a source directory and a baseline, the
// input it reads; nothing stands in for another component, and the command
// has no backend to reach.
// Rule 7: one test, the command line's whole story: a well-formed line runs
// (`scan src --baseline baseline.json` scans and passes), then each way a line
// is refused, one step each: no command, an unknown command, an option without
// its value, an option the command does not have, the wrong number of
// operands. After every step the case's files are read back byte for byte and
// its home read back empty: a refused line reads and writes nothing. The
// other commands' own lines are refused in their own tests
// (tests/warnings/standard.mjs, tests/tools/census.mjs, tests/tools/
// inventory.mjs, tests/guard/handrolled.mjs, tests/tools/errors.mjs,
// tests/tools/generate.mjs).
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/lint-arguments-<pid>/home; the
// command has no backend variable of its own.
// Rule 9: every status and sentence below was copied from the command run by
// hand with `env -i` over the same seeded directory; only the case's paths
// are interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const USAGE =
  'node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json] | catalogue <catalogue.json> [--repository <dir>] [--sources <path>,...] [--entries <entries.json>] [--json] | errors [--json]';
// The statuses the command answered: nothing refused, a refusal of how it was started.
const EXIT_SUCCESS = 0;
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

// The whole run of a refusal of the layer's cause `id`: nothing on stdout, the three lines on stderr.
const refused = (id, sentence, remedy) => ({
  status: USAGE_EXIT,
  stdout: '',
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.arguments.${id}; ${PAGE}#wisent_errors-lint-arguments-${id}\n`,
});

test('the_error_standard_runs_a_well_formed_command_line_and_refuses_every_other', () => {
  const dir = join(root, 'target', 'real-tests', `lint-arguments-${process.pid}`);
  const home = join(dir, 'home');
  const work = join(dir, 'work');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  mkdirSync(join(work, 'src'), { recursive: true });
  const seeded = { 'baseline.json': '{}\n', 'src/main.rs': 'fn main() {}\n' };
  for (const [path, text] of Object.entries(seeded)) writeFileSync(join(work, path), text);
  const standard = (...words) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), ...words], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(filesUnder(work), seeded, `${step}: the directory is left as it was`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    assert.deepEqual(standard('scan', 'src', '--baseline', 'baseline.json'), {
      status: EXIT_SUCCESS,
      stdout: '1 source file(s), 0 generic sentence(s), 0 refused, 0 stale baseline entries\n',
      stderr: '',
    });
    untouched('a well-formed line');

    assert.deepEqual(
      standard(),
      refused(
        'command-absent',
        'starting ci/error-standard.mjs: no command was named, and ci/error-standard.mjs does nothing without one; observed: commands: scan, catalogue, errors',
        `name one of them: ${USAGE}`,
      ),
    );
    untouched('no command');

    assert.deepEqual(
      standard('lint'),
      refused('command-unknown', 'starting ci/error-standard.mjs: "lint" is not one of its commands; observed: commands: scan, catalogue, errors', `name one of them: ${USAGE}`),
    );
    untouched('an unknown command');

    assert.deepEqual(
      standard('scan', 'src', '--baseline'),
      refused(
        'option-without-value',
        'reading the options of ci/error-standard.mjs: --baseline is the last word, or the word after it is another option, so it names nothing; observed: the words given: scan src --baseline',
        `give --baseline its value: ${USAGE}`,
      ),
    );
    untouched('an option without its value');

    assert.deepEqual(
      standard('scan', 'src', '--strict'),
      refused(
        'option-unknown',
        'reading the options of ci/error-standard.mjs: --strict is not one of its options, and nothing it does reads it; observed: the words given: scan src --strict',
        `drop --strict or spell it as one of its options: ${USAGE}`,
      ),
    );
    untouched('an unknown option');

    assert.deepEqual(
      standard('catalogue', 'a.json', 'b.json'),
      refused(
        'operands-miscounted',
        'reading the operands of ci/error-standard.mjs: it takes exactly one catalogue file and was given 2; observed: operands given: a.json b.json',
        `name exactly one catalogue file: ${USAGE}`,
      ),
    );
    untouched('two operands where one is taken');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
