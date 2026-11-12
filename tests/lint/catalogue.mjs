// Real tests of `node ci/error-standard.mjs catalogue`: a cause holding a
// placeholder the renderer never fills or one no raising site passes, a cause
// whose test the repository neither holds nor lists as untested, a malformed
// list of untested causes, and an entry no functionality names. Each case is
// its own repository under the ignored target/, removed after.
//
//   node --test tests/lint/catalogue.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { catalogue } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const CAUSE = {
  id: 'value-unsafe', code: 'refused', usage: false,
  failed: 'checking the value {name}', cause: 'the value holds a quote the engine would read as the end of the string',
  observed: 'value {value}', remedy: 'quote {name} before passing it', test: 'tests/engine/values.rs::an_unsafe_value_is_refused',
};
const OPERATION = { id: 'example.engine.check', entries: ['example check'], uses: [], summary: 'check a value', docs: 'https://example.wisent.com/docs/errors', causes: [CAUSE] };
const SOURCE = 'fn raise(name: &str, value: &str) { refuse(&VALUE_UNSAFE, &[("name", name), ("value", value)]); }\n';
const TEST = '#[test]\nfn an_unsafe_value_is_refused() {}\n';

function check(name, { cause = CAUSE, files = {}, entries = null }) {
  const dir = join(root, 'target', 'real-tests', 'lint-catalogue', `${name}-${process.pid}`);
  rmSync(dir, { recursive: true, force: true });
  const all = { 'src/engine.rs': SOURCE, 'tests/engine/values.rs': TEST, ...files, 'errors.json': JSON.stringify([catalogue({ ...OPERATION, causes: [cause] }, 1)]) };
  if (entries !== null) all['entries.json'] = JSON.stringify(entries);
  for (const [path, text] of Object.entries(all)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  const words = ['catalogue', join(dir, 'errors.json'), '--repository', dir, ...(entries === null ? [] : ['--entries', join(dir, 'entries.json')])];
  try {
    return spawnSync(process.execPath, [join(root, 'ci', 'error-standard.mjs'), ...words], { encoding: 'utf8' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a_complete_catalogue_passes', () => {
  const result = check('complete', {});
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^ok {4}example\.engine\.check: 1 declared cause\(s\)/);
});

test('a_cause_with_an_unfilled_placeholder_is_refused', () => {
  const result = check('format-spec', { cause: { ...CAUSE, observed: 'value {value:?}', cause: '{error}' } });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /FAIL {2}example\.engine\.check: 1 declared cause\(s\)\n {8}Error: holding example\.engine\.check to the declaration rules: 4 of its declarations break a rule/);
  assert.match(result.stdout, /cause value-unsafe: `observed` holds the placeholder \{value:\?\}, which the renderer never fills/);
  assert.match(result.stdout, /cause value-unsafe: `cause` names \{error\}, the raw text of the layer below/);
  assert.match(result.stdout, /cause value-unsafe: `cause` is only "\{error\}", the text it wraps, so it says nothing of why/);
});

test('a_placeholder_no_raising_site_passes_is_refused', () => {
  const result = check('unpassed', { cause: { ...CAUSE, remedy: 'quote {name} for the engine {engine}' } });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /holding example\.engine\.check\.value-unsafe to the values its raising sites pass: `remedy` names \{engine\}, and no raising site in .* passes a value of that name, so every reader would see \{engine\} as written; observed: 1 source file\(s\) read; value names passed: name, value; fix: pass engine where the cause is raised, or take \{engine\} out of `remedy`/);
});

test('a_cause_whose_test_is_absent_is_refused', () => {
  const result = check('untested', { files: { 'tests/engine/values.rs': '// nothing here\n' } });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /reading the test example\.engine\.check\.value-unsafe names: .*values\.rs never names an_unsafe_value_is_refused, and .*untested-causes\.json does not list it/);
  const listed = check('listed', { files: { 'tests/engine/values.rs': '// nothing here\n', 'tests/untested-causes.json': JSON.stringify([{ test: CAUSE.test, reason: 'only the engine refuses it' }]) } });
  assert.equal(listed.status, 0, listed.stdout + listed.stderr);
});

test('a_malformed_untested_listing_is_refused', () => {
  const result = check('listing', { files: { 'tests/untested-causes.json': JSON.stringify([{ test: CAUSE.test }]) } });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /reading the untested causes .*untested-causes\.json: entry 1 is not a test path with a reason: it holds an object with test; observed: 1 entries/);
});

test('an_entry_no_functionality_names_is_refused', () => {
  const result = check('entries', { entries: ['example check', 'example purge'] });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /FAIL {2}Error: matching the entries in .*entries\.json to the declared functionalities: the entry "example purge" starts no declared functionality/);
});
