// Real test of `node ci/error-standard.mjs catalogue <listing> [--repository
// <dir>] [--sources <path>,...] [--entries <entries.json>] [--json]`, the
// command a consuming repository runs on the listing its own `errors list
// --json` printed, against its own checkout (README, "The lint a product
// runs"; docs/errors/lint.md, `wisent_errors.lint.catalogue`, "Started
// through: `node ci/error-standard.mjs catalogue`").
//
//   node --test tests/lint/catalogue.mjs
//
// Rule 4: `catalogue` is this package's own command, the program a consumer
// runs in its CI; it is started here as that process, with process.execPath,
// in a consumer's checkout seeded in the case: its source (src/engine.rs),
// its tests, its inventory of entries and the listing its `errors list
// --json` prints. Those files are the input the command reads, written the
// way a product leaves them, not stand-ins for another component; the
// command has no service, store or network to reach.
// Rule 5: every step asserts the exit status and the whole of stdout and
// stderr (a refusal's three lines and every problem line), then reads the
// checkout back file by file, byte for byte: the command writes nothing, a
// refused listing, baseline or inventory is left as it was, and the case's
// home is read back empty.
// Rule 7: one test, `catalogue`'s whole story over one checkout: a complete
// listing passes (text and --json), then each way it is refused, one step
// each, the checkout changed between steps as a product's author would
// change it: a repository that is not there, a cause with placeholders the
// renderer never fills, a placeholder no raising site passes, a raising
// site under tests/ only `--sources` reads, a `--sources` path that is not
// there, a cause whose test is absent and then listed as untested, a
// malformed list of untested causes, an entry no functionality starts, an
// entry the inventory lacks and an inventory of the wrong shape. How the
// listing file itself is read is tests/lint/input.mjs; how the words are
// read, tests/lint/arguments.mjs.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside target/real-tests/lint-catalogue-<pid>/home; the
// command has no backend and no variable of its own, and reads only the
// paths it is named.
// Rule 9: every status, sentence and problem line below was copied from
// `catalogue` run by hand with `env -i` over the same seeded checkout; only
// the case's directory is interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
// The statuses `catalogue` answered: nothing refused, a refusal, a refusal of what it was named.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;

// One cause of the product's listing, as its `errors list --json` prints it.
const CAUSE = {
  id: 'value-unsafe',
  code: 'refused',
  exit: 1,
  retryable: false,
  usage: false,
  failed: 'checking the value {name}',
  cause: 'the value holds a quote the engine would read as the end of the string',
  observed: 'value {value}',
  remedy: 'quote {name} before passing it',
  test: 'tests/engine/values.rs::an_unsafe_value_is_refused',
  doc: 'https://example.wisent.com/docs/errors#example-engine-check-value-unsafe',
};
// The product's whole listing, its one functionality declaring `cause`.
const listing = (cause) =>
  JSON.stringify([
    { operation: 'example.engine.check', entries: ['example check'], uses: [], summary: 'check a value', docs: 'https://example.wisent.com/docs/errors', causes: [cause] },
  ]);
const SOURCE = 'fn raise(name: &str, value: &str) { refuse(&VALUE_UNSAFE, &[("name", name), ("value", value)]); }\n';
const TEST = '#[test]\nfn an_unsafe_value_is_refused() {}\n';
const UNTESTED = '// nothing here\n';
const OK = 'ok    example.engine.check: 1 declared cause(s)\n';
const PASSED = '1 functionality, 1 with a complete catalogue, 0 refused; 0 entries starting no declared functionality\n';
const REPORT = '{\n  "operations": [\n    {\n      "operation": "example.engine.check",\n      "entries": [\n        "example check"\n      ],\n      "causes": 1,\n      "problems": []\n    }\n  ],\n  "unstarted": []\n}\n';

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

// What `catalogue` prints for example.engine.check refused for `problems`.
const refusedOperation = (problems) =>
  'FAIL  example.engine.check: 1 declared cause(s)\n' +
  `        Error: holding example.engine.check to the declaration rules: ${problems.length} of its declarations break a rule, each named on its own line below; observed: ${problems.length} line(s) below\n` +
  '        fix: change each declaration as its line says, then run the check again\n' +
  `        cause: wisent_errors.lint.catalogue.declaration-refused; ${PAGE}#wisent_errors-lint-catalogue-declaration-refused\n` +
  problems.map((problem) => `        ${problem}\n`).join('') +
  '1 functionality, 0 with a complete catalogue, 1 refused; 0 entries starting no declared functionality\n';

// The problem line of a placeholder {name} in `field` no raising site of the checkout passes.
const unpassed = (field, name) =>
  `holding example.engine.check.value-unsafe to the values its raising sites pass: \`${field}\` names {${name}}, and no raising site in . passes a value of that name, so every reader would see {${name}} as written; observed: 1 source file(s) read; value names passed: name, value; fix: pass ${name} where the cause is raised, or take {${name}} out of \`${field}\``;

test('catalogue_holds_a_products_listing_and_checkout_to_the_declaration_rules', () => {
  const dir = join(root, 'target', 'real-tests', `lint-catalogue-${process.pid}`);
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
  const remove = (path) => {
    rmSync(join(work, path), { recursive: true });
    for (const name of Object.keys(files)) if (name === path || name.startsWith(`${path}/`)) delete files[name];
  };
  const catalogue = (...words) => {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), 'catalogue', 'errors.json', ...words], { cwd: work, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(filesUnder(work), files, `${step}: the checkout holds what was written, and nothing more`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    write('src/engine.rs', SOURCE);
    write('tests/engine/values.rs', TEST);
    write('errors.json', listing(CAUSE));

    assert.deepEqual(catalogue('--repository', '.'), { status: EXIT_SUCCESS, stdout: OK + PASSED, stderr: '' });
    untouched('a complete listing');
    assert.deepEqual(catalogue('--repository', '.', '--json'), { status: EXIT_SUCCESS, stdout: REPORT, stderr: '' });
    untouched('a complete listing, as JSON');

    assert.deepEqual(catalogue('--repository', 'gone'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.paths',
        'path-absent',
        `opening the repository gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${work} exists and holds 3 entries: errors.json, src, tests`,
        `name the repository as it exists; a relative path is read from ${work}`,
      ),
    });
    untouched('a repository that is not there');

    write('errors.json', listing({ ...CAUSE, cause: '{error}', observed: 'value {value:?}' }));
    assert.deepEqual(catalogue('--repository', '.'), {
      status: EXIT_FAILURE,
      stdout: refusedOperation([
        "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
        'cause value-unsafe: `cause` is only "{error}", the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`',
        "cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted",
        unpassed('cause', 'error'),
      ]),
      stderr: '',
    });
    untouched('placeholders the renderer never fills');

    write('errors.json', listing({ ...CAUSE, remedy: 'quote {name} for the engine {engine}' }));
    assert.deepEqual(catalogue('--repository', '.'), { status: EXIT_FAILURE, stdout: refusedOperation([unpassed('remedy', 'engine')]), stderr: '' });
    untouched('a placeholder no raising site passes');

    // The one site passing `engine` is a command under tests/, which the walk skips; `--sources` names it.
    write('tests/commands/raise.mjs', 'refuse(VALUE_UNSAFE, { engine: chosen });\n');
    assert.deepEqual(catalogue('--repository', '.'), { status: EXIT_FAILURE, stdout: refusedOperation([unpassed('remedy', 'engine')]), stderr: '' });
    untouched('a raising site under tests/, not named');
    assert.deepEqual(catalogue('--repository', '.', '--sources', 'src,tests/commands/raise.mjs'), { status: EXIT_SUCCESS, stdout: OK + PASSED, stderr: '' });
    untouched('a raising site under tests/, named by --sources');

    assert.deepEqual(catalogue('--repository', '.', '--sources', 'src,gone'), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.paths',
        'path-absent',
        `opening a source directory of the repository gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${work} exists and holds 3 entries: errors.json, src, tests`,
        `name a source directory of the repository as it exists; a relative path is read from ${work}`,
      ),
    });
    untouched('a --sources path that is not there');

    remove('tests/commands');
    write('errors.json', listing(CAUSE));
    write('tests/engine/values.rs', UNTESTED);
    assert.deepEqual(catalogue('--repository', '.'), {
      status: EXIT_FAILURE,
      stdout: refusedOperation([
        'reading the test example.engine.check.value-unsafe names: tests/engine/values.rs never names an_unsafe_value_is_refused, and tests/untested-causes.json does not list it with the reason it cannot be provoked locally; observed: tests/engine/values.rs::an_unsafe_value_is_refused; fix: write that test, name the one that provokes the cause, or list tests/engine/values.rs::an_unsafe_value_is_refused in tests/untested-causes.json with why no local state can provoke it',
      ]),
      stderr: '',
    });
    untouched('a cause whose test is absent');

    write('tests/untested-causes.json', '[{"test": "tests/engine/values.rs::an_unsafe_value_is_refused", "reason": "only the engine refuses it"}]');
    assert.deepEqual(catalogue('--repository', '.'), { status: EXIT_SUCCESS, stdout: OK + PASSED, stderr: '' });
    untouched('a cause listed as untested with its reason');

    write('tests/untested-causes.json', '[{"test": "tests/engine/values.rs::an_unsafe_value_is_refused"}]');
    assert.deepEqual(catalogue('--repository', '.'), {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.catalogue',
        'untested-listing-malformed',
        'reading the untested causes tests/untested-causes.json: entry 1 is not a test path with a reason: it holds an object with test; observed: 1 entries',
        'write each entry as {"test": "tests/<area>/<file>::<name>", "reason": "why no local state provokes it"}',
      ),
    });
    untouched('an untested cause listed without its reason');

    remove('tests/untested-causes.json');
    write('tests/engine/values.rs', TEST);
    write('entries.json', '["example check", "example purge"]');
    assert.deepEqual(catalogue('--repository', '.', '--entries', 'entries.json'), {
      status: EXIT_FAILURE,
      stdout:
        OK +
        `FAIL  ${refusal(
          'wisent_errors.lint.catalogue',
          'entry-unstarted',
          'matching the entries in entries.json to the declared functionalities: the entry "example purge" starts no declared functionality, so whoever meets its failures has no declaration to read; observed: 2 entries listed, 1 functionalities declared',
          'declare every functionality it runs and name "example purge" in their entries',
        )}` +
        '1 functionality, 1 with a complete catalogue, 0 refused; 1 entry starting no declared functionality\n',
      stderr: '',
    });
    untouched('an entry no functionality starts');

    write('entries.json', '[]');
    assert.deepEqual(catalogue('--repository', '.', '--entries', 'entries.json'), {
      status: EXIT_FAILURE,
      stdout: refusedOperation([
        'operation example.engine.check: it names the entry "example check", which the 0 entries of entries.json do not hold; add it there, or drop it from the entries',
      ]),
      stderr: '',
    });
    untouched('an entry the inventory lacks');

    write('entries.json', '{"entries": ["example check"]}');
    assert.deepEqual(catalogue('--repository', '.', '--entries', 'entries.json'), {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        'wisent_errors.lint.input',
        'input-wrong-shape',
        'reading the entries entries.json: the file is JSON but not a list of strings, one per command, route, screen and routine; observed: it holds an object with entries',
        'write the entries as a list of strings, one per command, route, screen and routine',
      ),
    });
    untouched('an inventory of the wrong shape');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
