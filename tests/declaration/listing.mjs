// The declaration rules a product's causes are held to, the way the fleet
// holds them: a product prints its functionalities as its `errors list
// --json` through this package (`catalogue`, the public entry point of
// @wisent/errors), and its CI runs this package's own command over that
// listing, `node ci/error-standard.mjs catalogue <listing>`, which refuses a
// placeholder the renderer never fills, a cause that only wraps the raw text
// below it, raw text outside `observed` and a test that is not
// `tests/<area>/<file>::<name>` (catalogue/declaration.json, the same rules in
// every runtime). This test is that product: each step writes the listing the
// runtime prints, runs the command as a process and reads back what it left.
// It replaces tests/declaration/placeholders.py: the operator runs no Python,
// and the gates run this repository's node, Rust and Swift tests only.
//
//   node --test tests/declaration/listing.mjs
//
// How it keeps the test contract:
// - Rule 4: it drives the real command a consuming repository runs (README,
//   "The lint a product runs"; docs/errors/lint.md, "Started through: node
//   ci/error-standard.mjs catalogue") over the listing a product prints
//   through the package's public entry point; no internal module is imported,
//   and the probes are those catalogue/declaration.json states for every
//   runtime.
// - Rule 5: each step asserts the command's exit status, its whole standard
//   output (the ok/FAIL line, the three-line Error/fix/cause refusal, every
//   problem line, the summary) and an empty standard error, then reads the
//   listing back byte for byte and the case's HOME and TMPDIR still empty:
//   the command writes nothing.
// - Rule 6: every way a declaration breaks the placeholder, raw-message and
//   test-path rules is a step, each refused with its whole sentence; the
//   declaration-refused refusal names the functionality, how many lines are
//   refused, and its fix.
// - Rule 7: one command, `error-standard catalogue` over a product's
//   listing, and its story: a listing every rule holds passes, each broken
//   declaration is refused, and the declaration mended passes again.
// - Rule 8: the command runs with its environment cleared and given only
//   PATH, HOME, TMPDIR and XDG_* inside target/real-tests/declaration-listing;
//   it reads only the listing it is named and has no backend of its own.
// - Rule 9: every expected line, exit status and suggested name was copied
//   from live runs of the command (env -i, HOME and TMPDIR in
//   target/real-tests) over listings of these same declarations.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { PROBES, catalogue } from '../../js/index.mjs';

const ROOT = resolve(import.meta.dirname, '..', '..');
const CASE = join(ROOT, 'target', 'real-tests', 'declaration-listing');

// A command that refused nothing, C's EXIT_SUCCESS:
// https://pubs.opengroup.org/onlinepubs/9799919799/functions/exit.html
const EXIT_SUCCESS = 0;
// The status wisent_errors.lint.catalogue.declaration-refused declares, C's EXIT_FAILURE.
const EXIT_FAILURE = 1;

const OPERATION = {
  id: 'example.engine.values',
  entries: ['example values check'],
  uses: [],
  summary: 'check a value before the engine reads it',
  docs: 'https://docs.example.com/errors/engine.md',
};

const CAUSE = {
  id: 'value-unsafe',
  code: 'refused',
  usage: false,
  failed: 'checking the value {name}',
  cause: 'the value holds a quote the engine would read as the end of the string',
  observed: 'value {value}',
  remedy: 'quote {name} before passing it',
  test: 'tests/engine/values.rs::an_unsafe_value_is_refused',
};

const PASSED =
  'ok    example.engine.values: 1 declared cause(s)\n' +
  '1 functionality, 1 with a complete catalogue, 0 refused; 0 entries starting no declared functionality\n';

/** The whole standard output of the command refusing the listing for `problems`. */
const refused = (problems) =>
  [
    'FAIL  example.engine.values: 1 declared cause(s)',
    `        Error: holding example.engine.values to the declaration rules: ${problems.length} of its declarations break a rule, each named on its own line below; observed: ${problems.length} line(s) below`,
    '        fix: change each declaration as its line says, then run the check again',
    '        cause: wisent_errors.lint.catalogue.declaration-refused; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md#wisent_errors-lint-catalogue-declaration-refused',
    ...problems.map((problem) => `        ${problem}`),
    '1 functionality, 0 with a complete catalogue, 1 refused; 0 entries starting no declared functionality',
  ].join('\n') + '\n';

const malformed = (field, placeholder, suggestion) =>
  `cause value-unsafe: \`${field}\` holds the placeholder ${placeholder}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write ${suggestion} and have the raising site pass the value already formatted`;

const wraps = (quoted) =>
  `cause value-unsafe: \`cause\` is only ${quoted}, the text it wraps, so it says nothing of why; state the reason in words (the file is not JSON, the server refused the token) and move the wrapped text into \`observed\``;

const testMalformed = (path) =>
  `cause value-unsafe: test ${JSON.stringify(path)} is not tests/<area>/<file>::<test name> (pattern ^tests/[^/:]+(?:/[^/:]+)+::[a-z0-9_]+$); name the real test that provokes it`;

// Each placeholder catalogue/declaration.json says the renderer never fills,
// with the name the command answered it should be written as.
const SUGGESTED = {
  'value:?': '{value}',
  'error:#': '{error}',
  Path: '{path}',
  '1st': '{st}',
  'host-name': '{host_name}',
  'deal.title': '{deal_title}',
  '': '{value}',
  ' name': '{name}',
};

test('a_products_listing_is_held_to_the_declaration_rules', () => {
  rmSync(CASE, { recursive: true, force: true });
  const home = join(CASE, 'home');
  const tmp = join(CASE, 'tmp');
  mkdirSync(home, { recursive: true });
  mkdirSync(tmp);
  const listing = join(CASE, 'errors-list.json');
  const env = {
    PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
    HOME: home,
    TMPDIR: tmp,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_DATA_HOME: join(home, '.local', 'share'),
    XDG_STATE_HOME: join(home, '.local', 'state'),
  };

  const check = (step, changed, problems) => {
    const written = `${JSON.stringify([catalogue({ ...OPERATION, causes: [{ ...CAUSE, ...changed }] }, EXIT_FAILURE)], null, 2)}\n`;
    writeFileSync(listing, written);
    const ran = spawnSync(process.execPath, [join(ROOT, 'ci', 'error-standard.mjs'), 'catalogue', listing], { cwd: ROOT, env, encoding: 'utf8' });
    assert.deepEqual(
      { status: ran.status, stdout: ran.stdout, stderr: ran.stderr },
      { status: problems.length ? EXIT_FAILURE : EXIT_SUCCESS, stdout: problems.length ? refused(problems) : PASSED, stderr: '' },
      step,
    );
    assert.equal(readFileSync(listing, 'utf8'), written, `${step}: the listing was changed`);
    assert.deepEqual(readdirSync(home), [], `${step}: the command wrote to HOME`);
    assert.deepEqual(readdirSync(tmp), [], `${step}: the command wrote to TMPDIR`);
  };

  check('a listing every rule holds', {}, []);
  check('a format spec in observed', { observed: 'value {value:?}' }, [malformed('observed', '{value:?}', '{value}')]);
  check('names the renderer never fills, and a brace never closed', { failed: 'checking {Path} and {deal.title}', remedy: 'quote {name before passing it' }, [
    malformed('failed', '{Path}', '{path}'),
    malformed('failed', '{deal.title}', '{deal_title}'),
    "cause value-unsafe: `remedy` opens a placeholder at \"{name before passing it\" that no '}' closes; close it as {name} or drop the '{'",
  ]);
  check('a brace never opened', { failed: 'checking a} value' }, [
    "cause value-unsafe: `failed` holds a '}' at \"checking a} value\" that no '{' opened; drop it, or open the placeholder it ends",
  ]);
  check('a cause that is only the raw message', { cause: '{error}' }, [
    "cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`",
    wraps('"{error}"'),
  ]);
  check('a cause that only wraps two values', { cause: '{code}: {reason}' }, [wraps('"{code}: {reason}"')]);
  check('raw text where it belongs, in observed', { observed: 'the parser said {problem}' }, []);

  assert.deepEqual(Object.keys(SUGGESTED).sort(), [...PROBES.placeholder.invalid].sort(), 'catalogue/declaration.json names other invalid placeholders than were probed');
  for (const name of PROBES.placeholder.valid) check(`the placeholder {${name}}`, { observed: `value {${name}}` }, []);
  for (const name of PROBES.placeholder.invalid) {
    check(`the placeholder {${name}}`, { observed: `value {${name}}` }, [malformed('observed', `{${name}}`, SUGGESTED[name])]);
  }

  for (const path of PROBES.test_path.valid) check(`the test ${path}`, { test: path }, []);
  for (const path of PROBES.test_path.invalid) check(`the test ${path}`, { test: path }, [testMalformed(path)]);

  check('the declaration mended', {}, []);
});
