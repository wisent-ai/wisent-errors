// Real test of `node ci/warning-standard.mjs <warnings.json> [--repository
// <dir>] [--confirmations <file>] [--json]`, the warning standard a consuming
// repository runs in its CI on the listing its own `warnings list --json`
// printed (README, "The lint a product runs"; docs/guides/warnings.md;
// docs/errors/lint.md, `wisent_errors.lint.warnings`, "Started through:
// `node ci/warning-standard.mjs`"), and the sentence a JavaScript product
// shows a caller before it asks for the confirmation.
//
//   node --test tests/warnings/standard.mjs
//
// Rule 4: the warning standard is this package's own command, the program a
// consumer runs; it is started here as that process, with process.execPath,
// in a consumer's checkout seeded in the case: the listing its `warnings
// list --json` prints (warnings.json), the inventory of entries that ask for
// a confirmation (confirmations.json) and the test a warning names
// (tests/purge/purge.sh). Those files are the input the command reads,
// written as a product leaves them, not stand-ins for another component: the
// command reads files and has no service, store or network to reach, so no
// other component is involved. The second test reads the sentence
// `unconfirmed` returns through the package's public entry point
// (js/index.mjs), as a JavaScript product imports it: that sentence, printed
// by the product, is the whole of what the function does; there is no
// process, file or state of the package behind it to drive or read.
// Rule 5: every step of the command asserts the exit status and the whole of
// stdout and stderr (each refusal's three lines, every problem line, the
// summary, the whole --json report), then reads the checkout back file by
// file, byte for byte: the command writes nothing and leaves each refused
// listing as it was, and the case's home is read back empty.
// Rule 7: one test, the warning standard's whole story over one checkout,
// changed between steps as a product's author would change it: a declared
// warning with its confirmation and its test passes (text and --json), then
// a confirmation no warning explains, a warning no confirmation puts before
// its caller, a warning of an unknown hazard, one with an empty safeguard,
// one linking no anchor and declared twice, one whose test the repository
// lacks, a repository that is not there, confirmations of the wrong shape
// and no listing named, each refused.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/warnings-standard-<pid>/home;
// the command has no backend and no variable of its own, and reads only the
// paths it is named.
// Rule 9: every status, sentence and problem line below was copied from the
// command run by hand with `env -i` over the same seeded checkout.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';
import { unconfirmed } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const USAGE = 'node ci/warning-standard.mjs <warnings.json> [--repository <dir>] [--confirmations <file>] [--json]';
// The statuses the command answered: nothing refused, a refusal, a refusal of how it was started.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;

// The warning of the product's purge, as its `warnings list --json` prints it.
const WARNING = {
  id: 'removed-for-good',
  hazard: 'irreversible',
  effect: '{id} and every saved version of it are removed',
  consequence: 'nothing restores them, not restore and not restore --at',
  safeguard: 'keep a copy with `example backup <directory>`, which `example backup restore` puts back',
  confirm: 'rerun with --yes',
  test: 'tests/purge/purge.sh::purge_without_yes_removes_nothing',
  doc: 'https://example.wisent.com/docs/warnings#example-item-purge-warning-removed-for-good',
};
const purge = (warnings) => ({ operation: 'example.item.purge', entries: ['example purge'], summary: 'remove a trashed item and every saved version for good', warnings });
const LIST = { operation: 'example.item.list', entries: ['example list'], summary: 'list item metadata', warnings: [] };
const listing = (...functionalities) => JSON.stringify({ functionalities });
const HELD = '# purge_without_yes_removes_nothing\n';
const ONE_REFUSED = '1 functionality, 1 declaring warnings, 1 refused; 0 confirmations with no declared warning\n';

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

// What the command prints for example.item.purge declaring `declared` warnings, refused for `problems`, then `summary`.
const refusedPurge = (declared, problems, summary) =>
  `FAIL  example.item.purge: ${declared} declared warning(s)\n` +
  `        Error: holding example.item.purge to the warning rules: ${problems.length} of its warning declarations break a rule, each named on its own line; observed: ${problems.length} line(s) below\n` +
  '        fix: change each declaration as its line says, then run the check again\n' +
  `        cause: wisent_errors.lint.warnings.warning-refused; ${PAGE}#wisent_errors-lint-warnings-warning-refused\n` +
  problems.map((problem) => `        ${problem}\n`).join('') +
  summary;

test('the_warning_standard_holds_a_products_warnings_to_their_confirmations_and_tests', () => {
  const dir = join(root, 'target', 'real-tests', `warnings-standard-${process.pid}`);
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
  const standard = (...words) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'warning-standard.mjs'), ...words], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const check = (...extra) => standard('warnings.json', '--repository', '.', '--confirmations', 'confirmations.json', ...extra);
  const untouched = (step) => {
    assert.deepEqual(filesUnder(work), files, `${step}: the checkout holds what was written, and nothing more`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    write('tests/purge/purge.sh', HELD);
    write('warnings.json', listing(purge([WARNING]), LIST));
    write('confirmations.json', '["example purge"]');
    assert.deepEqual(check(), {
      status: EXIT_SUCCESS,
      stdout: 'ok    example.item.purge: 1 declared warning(s)\n2 functionalities, 1 declaring warnings, 0 refused; 0 confirmations with no declared warning\n',
      stderr: '',
    });
    untouched('a warning with its confirmation and its test');
    assert.deepEqual(check('--json'), {
      status: EXIT_SUCCESS,
      stdout: `${JSON.stringify(
        {
          operations: [
            { operation: 'example.item.purge', entries: ['example purge'], warnings: 1, problems: [] },
            { operation: 'example.item.list', entries: ['example list'], warnings: 0, problems: [] },
          ],
          unwarned: [],
        },
        null,
        2,
      )}\n`,
      stderr: '',
    });
    untouched('a warning with its confirmation and its test, as JSON');

    write('warnings.json', listing(purge([]), LIST));
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout:
        `FAIL  ${refusal(
          'wisent_errors.lint.warnings',
          'confirmation-unwarned',
          'matching the confirmations in confirmations.json to the declared warnings: the entry "example purge" asks for a confirmation, but no functionality it starts declares what the confirmation is for; observed: functionalities it starts: example.item.purge',
          'declare the warning, or stop asking for a confirmation nothing needs',
        )}` + '2 functionalities, 0 declaring warnings, 0 refused; 1 confirmation with no declared warning\n',
      stderr: '',
    });
    untouched('a confirmation no warning explains');

    write('warnings.json', listing(purge([WARNING]), LIST));
    write('confirmations.json', '[]');
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout: refusedPurge(
        1,
        [
          'operation example.item.purge: it declares 1 warning(s), but none of its entries (example purge) asks for a confirmation in confirmations.json, so the warning is never read before it runs; ask for one, or drop a warning nothing needs (warnings removed-for-good; confirmations.json lists no entry)',
        ],
        '2 functionalities, 1 declaring warnings, 1 refused; 0 confirmations with no declared warning\n',
      ),
      stderr: '',
    });
    untouched('a warning no confirmation puts before its caller');

    write('confirmations.json', '["example purge"]');
    write('warnings.json', listing(purge([{ ...WARNING, hazard: 'scary' }])));
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout: refusedPurge(
        1,
        ['warning removed-for-good: hazard "scary" is not one of irreversible, overwrites, cuts-off-access, exposes-secret, external-change, costs-money; pick the loss the caller cannot take back'],
        ONE_REFUSED,
      ),
      stderr: '',
    });
    untouched('a warning of an unknown hazard');

    write('warnings.json', listing(purge([{ ...WARNING, safeguard: ' ' }])));
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout: refusedPurge(1, ['warning removed-for-good: `safeguard` is empty; write what keeps a way back, done before confirming'], ONE_REFUSED),
      stderr: '',
    });
    untouched('a warning with an empty safeguard');

    write('warnings.json', listing(purge([{ ...WARNING, doc: 'https://example.wisent.com/docs/warnings' }, WARNING])));
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout: refusedPurge(
        2,
        [
          'operation example.item.purge: warning removed-for-good links doc "https://example.wisent.com/docs/warnings", which is not an anchor on an https warnings page; print https://example.wisent.com/docs/warnings#example-item-purge-warning-removed-for-good, as the runtime\'s warnings listing writes it',
          'operation example.item.purge: warning removed-for-good is declared twice; keep one declaration per id',
        ],
        ONE_REFUSED,
      ),
      stderr: '',
    });
    untouched('a warning linking no anchor, declared twice');

    write('warnings.json', listing(purge([WARNING])));
    assert.deepEqual(standard('warnings.json', '--repository', 'gone', '--confirmations', 'confirmations.json'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.paths',
        'path-absent',
        `opening the repository gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${work} exists and holds 3 entries: confirmations.json, tests, warnings.json`,
        `name the repository as it exists; a relative path is read from ${work}`,
      ),
    });
    untouched('a repository that is not there');

    write('confirmations.json', '{"entries": ["example purge"]}');
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.input',
        'input-wrong-shape',
        'reading the confirmations confirmations.json: the file is JSON but not a list of the entries that ask for a confirmation; observed: it holds an object with entries',
        'write the confirmations as a list of the entries that ask for a confirmation',
      ),
    });
    untouched('confirmations of the wrong shape');

    write('confirmations.json', '["example purge"]');
    rmSync(join(work, 'tests'), { recursive: true });
    delete files['tests/purge/purge.sh'];
    assert.deepEqual(check(), {
      status: EXIT_FAILURE,
      stdout: refusedPurge(
        1,
        [
          'example.item.purge.removed-for-good names the test tests/purge/purge.sh::purge_without_yes_removes_nothing, which the repository does not hold: tests/purge/purge.sh is absent; write that test, or name the one that shows this warning (repository .)',
        ],
        ONE_REFUSED,
      ),
      stderr: '',
    });
    untouched('a warning whose test the repository lacks');

    assert.deepEqual(standard(), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.arguments',
        'operands-miscounted',
        'reading the operands of ci/warning-standard.mjs: it takes exactly one warnings catalogue and was given 0; observed: operands given: (none)',
        `name exactly one warnings catalogue: ${USAGE}`,
      ),
    });
    untouched('no listing named');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an_unconfirmed_caller_reads_the_effect_the_loss_the_way_back_and_how_to_go_ahead', () => {
  assert.equal(
    unconfirmed(WARNING, { id: 'github' }),
    'github and every saved version of it are removed; nothing restores them, not restore and not restore --at; nothing was done. ' +
      'Before confirming: keep a copy with `example backup <directory>`, which `example backup restore` puts back. To go ahead: rerun with --yes',
  );
});
