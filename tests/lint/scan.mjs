// Real test of `node ci/error-standard.mjs scan <dir>... [--baseline <file>]
// [--json]`, the command a consuming repository runs on its own source to
// refuse an error message that says a failure happened without saying which
// (README, "The lint a product runs"; docs/errors/lint.md,
// `wisent_errors.lint.scan`, "Started through: `node ci/error-standard.mjs
// scan`").
//
//   node --test tests/lint/scan.mjs
//
// Rule 4: `scan` is this package's own command, the program a consumer runs
// in its CI; it is started here as that process, with process.execPath, in
// a consumer's checkout seeded in the case: its source directory and its
// baseline are the input the command reads, written the way a product keeps
// them, not stand-ins for another component. The command has no service,
// store or network to reach.
// Rule 5: every step asserts the exit status and the whole of stdout and
// stderr (each refusal's three lines, the summary line, the whole --json
// report), then reads the checkout back file by file, byte for byte: `scan`
// writes nothing, never rewrites the baseline it refuses, and the case's
// home is read back empty.
// Rule 6: every answer `scan` gives is a step: a clean tree passes, a
// generic sentence beyond the baseline is refused (text and --json, and with
// no baseline at all), a test file and a tests/ directory are not read, a
// sentence the baseline allows passes and is reported, a baseline above what
// the file holds is refused as stale, and a baseline that is not
// `{"<path>": {"<sentence>": <count>}}` is refused naming the entry that
// breaks it (a list, a path holding a number, a count that is a string). Each
// refusal names the file, the line, the sentence, the counts and the fix.
// How the directories named are opened is tests/lint/paths.mjs.
// Rule 7: one test, `scan`'s whole story over one checkout, its source and
// baseline changed between steps as a product's author would change them.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/lint-scan-<pid>/home; the
// command has no backend and no variable of its own, and reads only the
// paths it is named.
// Rule 9: every status, sentence and report below was copied from `scan`
// run by hand with `env -i` over the same seeded checkout.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
// The statuses `scan` answered: nothing refused, a refusal.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const CLEAN = 'fn main() {\n    eprintln!("pushing {branch}: the remote refused the ref");\n}\n';
const HELD = 'fn main() {\n    eprintln!("the push did not succeed");\n}\n';
const REASON = 'says the operation failed without the step, the cause or the fix';
const FINDING = { path: 'src/main.rs', line: 2, sentence: 'did not succeed', reason: REASON, text: 'eprintln!("the push did not succeed");' };

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

// The refusal of line 2 of src/main.rs, held once while the baseline allows none.
const HELD_REFUSAL = refusal(
  'wisent_errors.lint.scan',
  'generic-sentence-held',
  `holding src/main.rs to the error standard: line 2 says "did not succeed", which ${REASON}, and the baseline allows 0 of it in this file while it holds 1; observed: eprintln!("the push did not succeed");`,
  'declare the cause and raise it, saying what failed, why, the state observed and what fixes it, in place of the sentence',
);

// The whole run of a baseline refused for what it holds.
const malformed = (found) => ({
  status: EXIT_FAILURE,
  stdout: '',
  stderr: refusal(
    'wisent_errors.lint.input',
    'input-wrong-shape',
    `reading the baseline baseline.json: the file is JSON but not {"<path>": {"<sentence>": <count>}}; observed: it holds ${found}`,
    'write the baseline as {"<path>": {"<sentence>": <count>}}',
  ),
});

test('scan_refuses_a_generic_error_sentence_beyond_the_baseline_and_a_baseline_that_no_longer_holds', () => {
  const dir = join(root, 'target', 'real-tests', `lint-scan-${process.pid}`);
  const home = join(dir, 'home');
  const work = join(dir, 'work');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  const files = {};
  const write = (path, text) => {
    mkdirSync(dirname(join(work, path)), { recursive: true });
    writeFileSync(join(work, path), text);
    files[path] = text;
  };
  const scan = (...words) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'scan', 'src', ...words], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(filesUnder(work), files, `${step}: the checkout holds what was written, and nothing more`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    write('src/main.rs', CLEAN);
    write('baseline.json', '{}');
    assert.deepEqual(scan('--baseline', 'baseline.json'), { status: EXIT_SUCCESS, stdout: '1 source file(s), 0 generic sentence(s), 0 refused, 0 stale baseline entries\n', stderr: '' });
    untouched('a tree with no generic sentence');

    write('src/main.rs', HELD);
    assert.deepEqual(scan('--baseline', 'baseline.json'), {
      status: EXIT_FAILURE,
      stdout: `${HELD_REFUSAL}1 source file(s), 1 generic sentence(s), 1 refused, 0 stale baseline entries\n`,
      stderr: '',
    });
    untouched('a generic sentence the baseline does not allow');
    assert.deepEqual(scan('--baseline', 'baseline.json', '--json'), {
      status: EXIT_FAILURE,
      stdout: `${JSON.stringify({ files: 1, findings: [FINDING], refused: [{ ...FINDING, allowed: 0, held: 1 }], stale: [] }, null, 2)}\n`,
      stderr: '',
    });
    untouched('a generic sentence the baseline does not allow, as JSON');
    assert.deepEqual(scan(), {
      status: EXIT_FAILURE,
      stdout: `${HELD_REFUSAL}1 source file(s), 1 generic sentence(s), 1 refused, 0 stale baseline entries\n`,
      stderr: '',
    });
    untouched('a generic sentence and no baseline');

    // A test file and a tests/ directory hold sentences a test provokes, not a product's: neither is read.
    write('src/push.test.mjs', "throw new Error('the push did not succeed');\n");
    write('src/tests/push.rs', 'fn t() { panic!("the push did not succeed"); }\n');
    write('baseline.json', '{"src/main.rs": {"did not succeed": 1}}');
    assert.deepEqual(scan('--baseline', 'baseline.json'), { status: EXIT_SUCCESS, stdout: '1 source file(s), 1 generic sentence(s), 0 refused, 0 stale baseline entries\n', stderr: '' });
    untouched('a sentence the baseline allows');
    assert.deepEqual(scan('--baseline', 'baseline.json', '--json'), {
      status: EXIT_SUCCESS,
      stdout: `${JSON.stringify({ files: 1, findings: [FINDING], refused: [], stale: [] }, null, 2)}\n`,
      stderr: '',
    });
    untouched('a sentence the baseline allows, as JSON');

    write('baseline.json', '{"src/main.rs": {"did not succeed": 3}}');
    assert.deepEqual(scan('--baseline', 'baseline.json'), {
      status: EXIT_FAILURE,
      stdout:
        refusal(
          'wisent_errors.lint.scan',
          'baseline-stale',
          'holding src/main.rs to the baseline baseline.json: the baseline allows 3 of "did not succeed" in the file while it holds 1, and a baseline only shrinks; observed: 1 held, 3 allowed',
          'lower the entry for src/main.rs in baseline.json to 1',
        ) + '1 source file(s), 1 generic sentence(s), 0 refused, 1 stale baseline entry\n',
      stderr: '',
    });
    untouched('a baseline above what the file holds');

    write('baseline.json', '["src/main.rs"]');
    assert.deepEqual(scan('--baseline', 'baseline.json'), malformed('a list of 1'));
    untouched('a baseline that is a list');
    write('baseline.json', '{"src/main.rs": 1}');
    assert.deepEqual(scan('--baseline', 'baseline.json'), malformed('an object with src/main.rs, whose "src/main.rs" holds number 1 instead of its sentences'));
    untouched('a baseline path holding a number');
    write('baseline.json', '{"src/main.rs": {"did not succeed": "1"}}');
    assert.deepEqual(scan('--baseline', 'baseline.json'), malformed('an object with src/main.rs, whose "src/main.rs" gives "did not succeed" string "1" instead of a count'));
    untouched('a baseline count that is a string');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
