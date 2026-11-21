// Real tests of `node ci/error-standard.mjs catalogue`: a complete catalogue
// passes, a cause holding a placeholder the renderer never fills or one no
// raising site passes is refused, the raising sites `--sources` names are the
// ones read, a cause whose test the repository neither holds nor lists as
// untested is refused, a malformed list of untested causes is refused, and an
// entry no functionality names or one the inventory lacks is refused. Each
// case is its own repository under the ignored target/, removed after; each
// run's whole stdout and stderr are compared.
//
//   node --test tests/lint/catalogue.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';
import { catalogue } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const CAUSE = {
  id: 'value-unsafe', code: 'refused', usage: false,
  failed: 'checking the value {name}', cause: 'the value holds a quote the engine would read as the end of the string',
  observed: 'value {value}', remedy: 'quote {name} before passing it', test: 'tests/engine/values.rs::an_unsafe_value_is_refused',
};
const OPERATION = { id: 'example.engine.check', entries: ['example check'], uses: [], summary: 'check a value', docs: 'https://example.wisent.com/docs/errors', causes: [CAUSE] };
const SOURCE = 'fn raise(name: &str, value: &str) { refuse(&VALUE_UNSAFE, &[("name", name), ("value", value)]); }\n';
const TEST = '#[test]\nfn an_unsafe_value_is_refused() {}\n';
const OK = 'ok    example.engine.check: 1 declared cause(s)\n';
const PASSED = '1 functionality, 1 with a complete catalogue, 0 refused; 0 entries starting no declared functionality\n';

// `catalogue` over one case's repository; `{ dir, ran }`, the run's status and streams.
function check(name, { cause = CAUSE, files = {}, entries = null, extra = [] }) {
  const dir = join(root, 'target', 'real-tests', 'lint-catalogue', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  const all = { 'src/engine.rs': SOURCE, 'tests/engine/values.rs': TEST, ...files, 'errors.json': JSON.stringify([catalogue({ ...OPERATION, causes: [cause] }, 1)]) };
  if (entries !== null) all['entries.json'] = JSON.stringify(entries);
  for (const [path, text] of Object.entries(all)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  const words = ['catalogue', join(dir, 'errors.json'), '--repository', dir, ...(entries === null ? [] : ['--entries', join(dir, 'entries.json')]), ...extra];
  try {
    const ran = spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), ...words], { encoding: 'utf8' });
    return { dir, ran: { status: ran.status, stdout: ran.stdout, stderr: ran.stderr } };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// The three lines of a refusal of the catalogue check's cause `id`.
const refusal = (id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.lint.catalogue.${id}; ${PAGE}#wisent_errors-lint-catalogue-${id}`;

// What the check prints for example.engine.check refused for `problems`.
function refusedOperation(problems) {
  const head = refusal(
    'declaration-refused',
    `holding example.engine.check to the declaration rules: ${problems.length} of its declarations break a rule, each named on its own line below; observed: ${problems.length} line(s) below`,
    'change each declaration as its line says, then run the check again',
  );
  return (
    'FAIL  example.engine.check: 1 declared cause(s)\n' +
    `        ${head.split('\n').join('\n        ')}\n` +
    problems.map((problem) => `        ${problem}\n`).join('') +
    '1 functionality, 0 with a complete catalogue, 1 refused; 0 entries starting no declared functionality\n'
  );
}

// The problem line of a placeholder no raising site in `dir` passes.
const unpassed = (dir, field, name, passed = 'name, value') =>
  `holding example.engine.check.value-unsafe to the values its raising sites pass: \`${field}\` names {${name}}, and no raising site in ${dir} passes a value of that name, so every reader would see {${name}} as written; observed: 1 source file(s) read; value names passed: ${passed}; fix: pass ${name} where the cause is raised, or take {${name}} out of \`${field}\``;

test('a_complete_catalogue_passes', () => {
  const { ran } = check('complete', {});
  assert.deepEqual(ran, { status: EXIT_SUCCESS, stdout: OK + PASSED, stderr: '' });
  const json = check('complete-json', { extra: ['--json'] });
  assert.equal(json.ran.status, EXIT_SUCCESS, json.ran.stderr);
  assert.equal(json.ran.stderr, '');
  assert.deepEqual(JSON.parse(json.ran.stdout), { operations: [{ operation: 'example.engine.check', entries: ['example check'], causes: 1, problems: [] }], unstarted: [] });
});

test('a_cause_with_an_unfilled_placeholder_is_refused', () => {
  const { dir, ran } = check('format-spec', { cause: { ...CAUSE, observed: 'value {value:?}', cause: '{error}' } });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedOperation([
      "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
      'cause value-unsafe: `cause` is only "{error}", the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into `observed`',
      "cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted",
      unpassed(dir, 'cause', 'error'),
    ]),
    stderr: '',
  });
});

test('a_placeholder_no_raising_site_passes_is_refused', () => {
  const { dir, ran } = check('unpassed', { cause: { ...CAUSE, remedy: 'quote {name} for the engine {engine}' } });
  assert.deepEqual(ran, { status: EXIT_FAILURE, stdout: refusedOperation([unpassed(dir, 'remedy', 'engine')]), stderr: '' });
});

test('the_raising_sites_sources_names_are_the_ones_read', () => {
  // The only site passing `engine` is a command under tests/, which the walk skips.
  const setup = { cause: { ...CAUSE, remedy: 'quote {name} for the engine {engine}' }, files: { 'tests/commands/raise.mjs': 'refuse(VALUE_UNSAFE, { engine: chosen });\n' } };
  const skipped = check('sources-skipped', setup);
  assert.deepEqual(skipped.ran, { status: EXIT_FAILURE, stdout: refusedOperation([unpassed(skipped.dir, 'remedy', 'engine')]), stderr: '' });
  const named = check('sources-named', { ...setup, extra: ['--sources', 'src,tests/commands/raise.mjs'] });
  assert.deepEqual(named.ran, { status: EXIT_SUCCESS, stdout: OK + PASSED, stderr: '' });
});

test('a_cause_whose_test_is_absent_is_refused', () => {
  const { dir, ran } = check('untested', { files: { 'tests/engine/values.rs': '// nothing here\n' } });
  const untested = join(dir, 'tests', 'untested-causes.json');
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedOperation([
      `reading the test example.engine.check.value-unsafe names: ${join(dir, 'tests', 'engine', 'values.rs')} never names an_unsafe_value_is_refused, and ${untested} does not list it with the reason it cannot be provoked locally; observed: ${CAUSE.test}; fix: write that test, name the one that provokes the cause, or list ${CAUSE.test} in ${untested} with why no local state can provoke it`,
    ]),
    stderr: '',
  });
  const listed = check('listed', { files: { 'tests/engine/values.rs': '// nothing here\n', 'tests/untested-causes.json': JSON.stringify([{ test: CAUSE.test, reason: 'only the engine refuses it' }]) } });
  assert.deepEqual(listed.ran, { status: EXIT_SUCCESS, stdout: OK + PASSED, stderr: '' });
});

test('a_malformed_untested_listing_is_refused', () => {
  const { dir, ran } = check('listing', { files: { 'tests/untested-causes.json': JSON.stringify([{ test: CAUSE.test }]) } });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: '',
    stderr: `${refusal(
      'untested-listing-malformed',
      `reading the untested causes ${join(dir, 'tests', 'untested-causes.json')}: entry 1 is not a test path with a reason: it holds an object with test; observed: 1 entries`,
      'write each entry as {"test": "tests/<area>/<file>::<name>", "reason": "why no local state provokes it"}',
    )}\n`,
  });
});

test('an_entry_no_functionality_names_is_refused', () => {
  const { dir, ran } = check('entries', { entries: ['example check', 'example purge'] });
  const entries = join(dir, 'entries.json');
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout:
      OK +
      `FAIL  ${refusal(
        'entry-unstarted',
        `matching the entries in ${entries} to the declared functionalities: the entry "example purge" starts no declared functionality, so whoever meets its failures has no declaration to read; observed: 2 entries listed, 1 functionalities declared`,
        'declare every functionality it runs and name "example purge" in their entries',
      )}\n` +
      '1 functionality, 1 with a complete catalogue, 0 refused; 1 entry starting no declared functionality\n',
    stderr: '',
  });
});

test('an_entry_the_inventory_lacks_is_refused', () => {
  const { dir, ran } = check('uninventoried', { entries: [] });
  assert.deepEqual(ran, {
    status: EXIT_FAILURE,
    stdout: refusedOperation([
      `operation example.engine.check: it names the entry "example check", which the 0 entries of ${join(dir, 'entries.json')} do not hold; add it there, or drop it from the entries`,
    ]),
    stderr: '',
  });
});
