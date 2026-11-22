// Real test of the parts loader (`wisent_errors.catalogue.parts`,
// codegen/parts.mjs) through `node ci/error-standard.mjs errors`, the first
// command that reads this package's own failure catalogue: every command of
// the package (the lint a consuming repository runs, the generator, the
// census, the inventory) raises its refusals from the parts under
// catalogue/failures/, so what the loader says of a part it cannot read is
// what any of them says (docs/errors/tools.md, `wisent_errors.catalogue.parts`).
//
//   node --test tests/tools/parts.mjs
//
// Rule 4: `errors` is the package's own command, started as a process with
// process.execPath, the way a reader starts it. It runs in a copy of the
// package (catalogue/, codegen/, ci/, js/) under
// target/real-tests/tools-parts-<pid>/package, because each step breaks the
// catalogue the way a checkout gets broken (a folder or a part a user may not
// read, a part deleted, cut short, hand-edited out of shape, copied over
// another, a use renamed) and the checkout's own catalogue must not be
// touched; the copy is the real package, nothing in it stands in for
// another component, and the loader has no backend.
// Rule 7: one test, the loader's whole story through `errors`: the intact
// catalogue read, a part moved into a subfolder read with the rest, then
// each refusal, one step each: the parts folder and a subfolder it may not
// list, no part at any depth, a part it may not read, a part cut short, a
// part of the wrong shape, an operation declared in two parts, a use no part
// declares. After every step the command's exit status and whole stdout and
// stderr are asserted, the catalogue is read back holding exactly what the
// step left (the loader writes nothing), the step is undone and the
// catalogue read back equal to the package's own again, and the case's home
// is read back empty. The one cause no part on disk can provoke, a command
// raising a cause no part declares, is listed in tests/untested-causes.json.
// Rule 8: the child's environment is cleared and given only PATH and HOME,
// TMPDIR and XDG_* inside the case's home; the loader has no backend
// variable, and reads only the catalogue beside the code it runs.
// Rule 9: every sentence below was copied from `errors` run by hand with
// `env -i` over a copy broken the same way. Interpolated are the copy's
// paths and the owner's uid, and what the catalogue itself declares, read
// back from the copy's parts because the catalogue grows: the listing, the
// number of parts and the declared operations.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
// The statuses `errors` answered: the catalogue printed, a refusal of the loader.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const LOADER = 'wisent_errors.catalogue.parts: parts-unlisted, parts-absent, part-unreadable, part-not-json, part-wrong-shape, operation-declared-twice, uses-undeclared, raised-undeclared\n';

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

// Every part under `failures` at any depth, as its path below it, in the order the loader reads them.
const partFiles = (failures) => readdirSync(failures, { recursive: true }).filter((name) => name.endsWith('.json')).sort();

// The operations the parts under `failures` declare for node, in path order.
const declared = (failures) =>
  partFiles(failures).flatMap((file) => JSON.parse(readFileSync(join(failures, file), 'utf8')).operations.filter((operation) => operation.runtimes.includes('node')));

// What `errors` prints for the parts under `failures`: the loader's own line, then each operation with its causes tested in JavaScript.
const listing = (failures) =>
  LOADER +
  declared(failures)
    .map((operation) => {
      const causes = operation.causes.filter((cause) => cause.tests.js !== undefined).map((cause) => cause.id);
      return `${operation.id}: ${causes.join(', ') || `uses ${operation.uses.join(', ')}`}\n`;
    })
    .join('');

// The whole run of a refusal of the loader's cause `id`.
const refused = (id, sentence, remedy) => ({
  status: EXIT_FAILURE,
  stdout: '',
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.catalogue.parts.${id}; ${PAGE}#wisent_errors-catalogue-parts-${id}\n`,
});

test('errors_reads_every_part_or_refuses_the_one_it_cannot', () => {
  const dir = join(root, 'target', 'real-tests', `tools-parts-${process.pid}`);
  const home = join(dir, 'home');
  const copy = join(dir, 'package');
  const failures = join(copy, 'catalogue', 'failures');
  const uid = process.getuid();
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  for (const part of ['catalogue', 'codegen', 'ci', 'js']) cpSync(join(root, part), join(copy, part), { recursive: true });
  const own = filesUnder(failures);
  const errors = () => {
    const ran = spawnSync(process.execPath, [join(copy, 'ci', 'error-standard.mjs'), 'errors'], { cwd: dir, env: isolated(home), encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  // After a step: the catalogue holds what the step left, the home nothing.
  const left = (step, files) => {
    assert.deepEqual(filesUnder(failures), files, `${step}: the loader leaves the catalogue as the step left it`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  // Once a step is undone: the copy's catalogue is the package's own again.
  const restored = (step) => assert.deepEqual(filesUnder(failures), own, `${step}: undone, the catalogue is the package's own`);
  const rewrite = (file, change) => {
    const text = change(own[file]);
    assert.notEqual(text, own[file], `${file} changes`);
    writeFileSync(join(failures, file), text);
    return { ...own, [file]: text };
  };
  try {
    assert.deepEqual(errors(), { status: EXIT_SUCCESS, stdout: listing(failures), stderr: '' });
    left('the intact catalogue', own);

    mkdirSync(join(failures, 'more', 'deeper'), { recursive: true });
    renameSync(join(failures, 'tools.json'), join(failures, 'more', 'deeper', 'tools.json'));
    const nested = listing(failures);
    assert.match(nested, /^wisent_errors\.census\.implementations: /m, 'the moved part declares the census');
    assert.deepEqual(errors(), { status: EXIT_SUCCESS, stdout: nested, stderr: '' });
    const { 'tools.json': tools, ...rest } = own;
    left('a part in a subfolder', { ...rest, 'more/deeper/tools.json': tools });
    renameSync(join(failures, 'more', 'deeper', 'tools.json'), join(failures, 'tools.json'));
    rmSync(join(failures, 'more'), { recursive: true });
    restored('a part in a subfolder');

    for (const folder of [failures, join(failures, 'lint')]) {
      chmodSync(folder, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
      const ran = errors();
      chmodSync(folder, 0o755); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
      assert.deepEqual(
        ran,
        refused(
          'parts-unlisted',
          `listing the failure catalogue parts in ${folder}: the directory cannot be listed, so no part of the catalogue can be read; observed: ${folder} is a directory of mode 0, owner uid ${uid}; the operating system answered EACCES: permission denied, scandir '${folder}'`,
          'restore it with `git checkout -- catalogue/failures`, or let the user running the command read it',
        ),
      );
      left(`${folder} it may not list`, own);
    }

    // Every part at any depth goes; the emptied lint/ subfolder stays, so a folder holding no part is not taken for one.
    for (const file of partFiles(failures)) rmSync(join(failures, file));
    writeFileSync(join(failures, 'notes.txt'), 'nothing');
    assert.deepEqual(
      errors(),
      refused(
        'parts-absent',
        `reading the failure catalogue parts in ${failures}: the directory holds no .json part, so this package would declare none of its own failures; observed: it holds lint, notes.txt`,
        'restore the parts with `git checkout -- catalogue/failures`',
      ),
    );
    left('no part at any depth', { 'notes.txt': 'nothing' });
    rmSync(join(failures, 'notes.txt'));
    for (const [file, text] of Object.entries(own)) writeFileSync(join(failures, file), text);
    restored('no part at any depth');

    const envelope = join(failures, 'envelope.json');
    chmodSync(envelope, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unreadable = errors();
    chmodSync(envelope, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(
      unreadable,
      refused(
        'part-unreadable',
        `reading the failure catalogue part ${envelope}: the part is listed but cannot be read; observed: ${envelope} is a file of mode 0, owner uid ${uid}; the operating system answered EACCES: permission denied, open '${envelope}'`,
        `let the user running the command read it (chmod u+r ${envelope}), or restore it with \`git checkout -- ${envelope}\``,
      ),
    );
    left('a part it may not read', own);

    const cut = rewrite('envelope.json', (text) => text.slice(0, 40));
    assert.deepEqual(
      errors(),
      refused(
        'part-not-json',
        `reading the failure catalogue part ${envelope}: the part is not JSON; observed: 40 bytes; the decoder answered Unexpected end of JSON input`,
        `correct the JSON of ${envelope}; \`jq . ${envelope}\` points at the place it stops parsing`,
      ),
    );
    left('a part cut short', cut);
    writeFileSync(envelope, own['envelope.json']);
    restored('a part cut short');

    const reshaped = rewrite('envelope.json', (text) => text.replaceAll('"tests": {', '"checks": {'));
    assert.deepEqual(
      errors(),
      refused(
        'part-wrong-shape',
        `reading the failure catalogue part ${envelope}: the part is JSON but not an object with an area and a list of operations, each with an id, runtimes, entries (one list, or one list per runtime) and causes carrying their tests; observed: at operations[0].causes[0].tests it holds nothing`,
        `write ${envelope} as an object with "area" and "operations", the way the other parts are written`,
      ),
    );
    left('a part of the wrong shape', reshaped);
    writeFileSync(envelope, own['envelope.json']);
    restored('a part of the wrong shape');

    writeFileSync(join(failures, 'zz-copy.json'), own['tools.json']);
    assert.deepEqual(
      errors(),
      refused(
        'operation-declared-twice',
        `reading the failure catalogue parts in ${failures}: the operation wisent_errors.census.implementations is declared in both ${join(failures, 'tools.json')} and ${join(failures, 'zz-copy.json')}; observed: ${partFiles(failures).length} part(s) read`,
        'keep wisent_errors.census.implementations in one part and delete it from the other',
      ),
    );
    left('an operation declared in two parts', { ...own, 'zz-copy.json': own['tools.json'] });
    rmSync(join(failures, 'zz-copy.json'));
    restored('an operation declared in two parts');

    // The census's uses end with lint.paths; renamed, no part declares what it uses.
    const renamed = rewrite('tools.json', (text) => text.replace('"wisent_errors.lint.paths"]', '"wisent_errors.lint.gone"]'));
    assert.deepEqual(
      errors(),
      refused(
        'uses-undeclared',
        `joining the failure catalogue parts in ${failures}: the operation wisent_errors.census.implementations uses wisent_errors.lint.gone, which no part declares; observed: declared operations: ${['wisent_errors.catalogue.parts', ...declared(failures).map((operation) => operation.id)].join(', ')}`,
        'declare wisent_errors.lint.gone in a part, or take it out of the uses of wisent_errors.census.implementations',
      ),
    );
    left('a use no part declares', renamed);
    writeFileSync(join(failures, 'tools.json'), own['tools.json']);
    restored('a use no part declares');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
