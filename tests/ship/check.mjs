// Real test of `node ci/check.mjs`, what must hold before this package
// ships: the generated code matches the catalogue, the envelope schema states
// the catalogue's vocabulary, the package's own failure catalogue holds in
// every runtime, and the node tests pass (docs/errors/tools.md,
// `wisent_errors.ship.check`, "Started through: `node ci/check.mjs`"; the
// `checks` gate of .wisent-release.json runs it).
//
//   node --test tests/ship/check.mjs
//
// Rule 4: the check is this package's own command, started as the process
// the gate starts, with process.execPath, in a copy of the whole package
// (every file of the checkout but .git, build output and caches) under
// target/real-tests/ship-check-<pid>/package, whose schema/failure.schema.json
// names one code more than catalogue/codes.json, the drift the check exists
// to refuse. Every step of the check runs for real in the copy: the
// generator's --check, the schema read, the catalogue held to its rules
// against the copy's tests and raising sites, and the copy's own node tests
// run by `node --test`. The copy leaves out this file: the copy's check
// would otherwise run this test again in a copy of its own, without end. The
// check has no backend; the copy is the package, not a stand-in.
// Rule 5: the run's exit status and whole stdout and stderr are asserted,
// then the copy's schema and catalogue are read back byte for byte (the
// check writes nothing), and the case's home back empty.
// Rule 6: the check's one declared cause, `vocabulary-differs`, is provoked
// whole; the copy also shows the check holding the catalogue to its own
// rule, as the copy lacks the test this cause names. The check passing is
// the `checks` gate itself, `node ci/check.mjs` run on the checkout, which
// runs this test among the node tests.
// Rule 7: one test, the check's story of a schema that drifted from the
// catalogue.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside the case's home; the check has no backend
// variable, and the node tests it starts set up their own cases.
// Rule 9: the lines of the first three checks, the refusal, the problem line
// and the summary were copied from `node ci/check.mjs` run by hand with
// `env -i` over a copy with the same schema change. The node-test line was
// not run by hand (running a test suite was not allowed while this was
// written): it is the check's own `ok    the node tests pass (<n> files)`
// for the copy's tests. The functionality counts are read from the copy's
// catalogue parts, as the check counts them, because the catalogue grows.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { basename, join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const TOOLS = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const SELF = 'tests/ship/check.mjs';
const NAME = 'check_refuses_a_schema_naming_other_codes_than_the_catalogue';
// The status the check answered: a check failed.
const EXIT_FAILURE = 1;
// What a checkout holds that is not the package: git's own, build output, caches.
const SCRATCH = new Set(['.git', 'target', '.build', 'node_modules', '__pycache__', 'wisent_errors.egg-info']);
const CODES = 'config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown';

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

test(NAME, () => {
  const dir = join(root, 'target', 'real-tests', `ship-check-${process.pid}`);
  const home = join(dir, 'home');
  const copy = join(dir, 'package');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  // Entry by entry: the case lives under the checkout's target/, and a directory is never copied into itself.
  for (const entry of readdirSync(root)) {
    if (SCRATCH.has(entry)) continue;
    cpSync(join(root, entry), join(copy, entry), { recursive: true, filter: (path) => !SCRATCH.has(basename(path)) && relative(root, path) !== SELF });
  }
  const schemaPath = join(copy, 'schema', 'failure.schema.json');
  const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
  schema.properties.error_code.enum.push('offline');
  writeFileSync(schemaPath, `${JSON.stringify(schema, null, 2)}\n`);
  const held = { schema: readFileSync(schemaPath, 'utf8'), catalogue: filesUnder(join(copy, 'catalogue')) };
  // The functionalities each runtime's catalogue holds, as the check counts them: node adds the parts loader's own.
  const parts = readdirSync(join(copy, 'catalogue', 'failures'), { recursive: true }).filter((name) => name.endsWith('.json'));
  const operations = parts.flatMap((name) => JSON.parse(readFileSync(join(copy, 'catalogue', 'failures', name), 'utf8')).operations);
  const count = (runtime) => operations.filter((operation) => operation.runtimes.includes(runtime)).length + (runtime === 'node' ? 1 : 0);
  const tests = readdirSync(join(copy, 'tests'), { withFileTypes: true })
    .filter((area) => area.isDirectory())
    .flatMap((area) => readdirSync(join(copy, 'tests', area.name)).filter((name) => name.endsWith('.mjs')));
  const untested = join(copy, 'tests', 'untested-causes.json');
  const node = `this package's own node failure catalogue holds (${count('node')} functionalities)`;
  try {
    const ran = spawnSync(process.execPath, [join(copy, 'ci', 'check.mjs')], { cwd: dir, env: isolated(home), encoding: 'utf8' });
    assert.deepEqual(
      { status: ran.status, stdout: ran.stdout, stderr: ran.stderr },
      {
        status: EXIT_FAILURE,
        stdout:
          'ok    generated code matches the catalogue\n' +
          'FAIL  schema and catalogue name the same codes\n' +
          `        Error: comparing the codes of schema/failure.schema.json with catalogue/codes.json: the schema names other codes than the catalogue, so a checked envelope and a generated runtime disagree; observed: catalogue ${CODES}; schema ${CODES}, offline\n` +
          '        fix: change schema/failure.schema.json to name what catalogue/codes.json names\n' +
          `        cause: wisent_errors.ship.check.vocabulary-differs; ${TOOLS}#wisent_errors-ship-check-vocabulary-differs\n` +
          'ok    schema and catalogue name the same severities\n' +
          'ok    the failure point pattern is stated once\n' +
          `FAIL  ${node}\n` +
          '        wisent_errors.ship.check:\n' +
          `          reading the test wisent_errors.ship.check.vocabulary-differs names: ${join(copy, SELF)} is absent, and ${untested} does not list it with the reason it cannot be provoked locally; observed: ${SELF}::${NAME}; fix: write that test, name the one that provokes the cause, or list ${SELF}::${NAME} in ${untested} with why no local state can provoke it\n` +
          ['js', 'rust', 'python', 'swift'].map((runtime) => `ok    this package's own ${runtime} failure catalogue holds (${count(runtime)} functionalities)\n`).join('') +
          `ok    the node tests pass (${tests.length} files)\n` +
          `\n2 check(s) failed: schema and catalogue name the same codes; ${node}\n`,
        stderr: '',
      },
    );
    assert.equal(readFileSync(schemaPath, 'utf8'), held.schema, 'the refused schema is left as it was');
    assert.deepEqual(filesUnder(join(copy, 'catalogue')), held.catalogue, 'the catalogue is left as it was');
    assert.deepEqual(readdirSync(home), [], 'nothing is written to the home');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
