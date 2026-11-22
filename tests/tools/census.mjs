// Real test of `node ci/find-implementations.mjs [<root>...]
// [--unadopted-only]`, the census an operator runs over the checkouts of the
// fleet to find every product that restates the envelope's vocabulary
// instead of depending on the package (docs/maintaining/finding-
// implementations.md; docs/errors/tools.md,
// `wisent_errors.census.implementations`, "Started through: `node
// ci/find-implementations.mjs`").
//
//   node --test tests/tools/census.mjs
//
// Rule 4: the census is this package's own command, started here as the
// process an operator starts, with process.execPath, over a root of product
// checkouts seeded in the case: a real git repository
// (products/example-product) whose files, manifest, commits and remote are
// made with git itself, the way a product's checkout is, and read by the
// census through the real git it starts. Nothing stands in for git or for
// a product; the census has no service or store of its own.
// Rule 7: one test, the census's whole story over one product changed step
// by step: a product restating the vocabulary counted and refused (all rows,
// --unadopted-only, and with no root, from a copy of the package beside the
// products so the parent it searches is the case's), a file it may not read
// and a git it cannot start refused, then a product that adopted the
// package listed with its pin and passing (all rows and --unadopted-only),
// a manifest naming the package with no revision listed unpinned, a stale
// checkout of a product whose remote tip no longer restates the vocabulary
// and a checkout with no remote told apart from a restating one, and a root
// that is not there, a root that is a file and an option it lacks refused.
// After every step the exit status and whole stdout and stderr are
// asserted, the product's files are read back byte for byte (the census
// writes nothing, changes no mode) and the case's home read back empty.
// Rule 8: the census and git are started with the environment cleared and
// given only PATH, HOME, TMPDIR and XDG_* inside
// target/real-tests/tools-census-<pid>/home, and GIT_CONFIG_NOSYSTEM so git
// reads no configuration outside the case; the census has no backend
// variable of its own, and git is its only other component.
// Rule 9: every status, row and sentence below was copied from the census
// run by hand with `env -i` over the same product made the same way; only
// the case's paths and the owner's uid are interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const TOOLS = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const LINT = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
// The statuses the census answered: nothing restated, a refusal, a refusal of what it was named.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;
const COPY = "export const CODES = ['config', 'auth', 'not_found', 'rate_limit', 'timeout', 'infra_down'];\n";
const CLEAN = "export const greeting = 'hello';\n";
const PIN = '0123456789abcdef0123456789abcdef01234567';
const LABEL = 'products/example-product';
// The census's closing lines: checkouts declaring the package, then rows quoting 5 of the 8 codes, by kind.
const SUMMARY = (declared, rows, live, stale, part) =>
  `\n${declared} checkout(s) declare a dependency on the package.\n${rows} still quote 5 or more codes as literals: ${live} restate the taxonomy, ${stale} are stale or detached copies of one that does not, ${part} are part-migrated and name the package too.\n`;

// The child's whole environment: PATH, a home, temporary directory and XDG directories inside the case, and git kept off the system's configuration.
const isolated = (home) => ({
  PATH: process.env.PATH,
  HOME: home,
  TMPDIR: home,
  XDG_CONFIG_HOME: join(home, '.config'),
  XDG_CACHE_HOME: join(home, '.cache'),
  XDG_DATA_HOME: join(home, '.local', 'share'),
  XDG_STATE_HOME: join(home, '.local', 'state'),
  GIT_CONFIG_NOSYSTEM: '1',
});

// Every file of a checkout but git's own, by its path below it, with what it holds.
const filesUnder = (dir) =>
  Object.fromEntries(
    readdirSync(dir, { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile() && !relative(dir, entry.parentPath).split('/').includes('.git'))
      .map((entry) => [relative(dir, join(entry.parentPath, entry.name)), readFileSync(join(entry.parentPath, entry.name), 'utf8')]),
  );

// The three lines of a refusal of `operation`'s cause `id`, listed on `page`.
const refusal = (page, operation, id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: ${operation}.${id}; ${page}#${operation.replaceAll('.', '-')}-${id}\n`;

// The census's refusal of a product under `roots` restating the vocabulary, labelled `label`.
const restated = (roots, label) =>
  refusal(
    TOOLS,
    'wisent_errors.census.implementations',
    'vocabulary-restated',
    `counting the implementations of the envelope under ${roots}: 1 repositories quote a majority of the catalogue's codes, infra_down among them, and depend on no revision of the package; observed: each repository with the files that restate it, a file counting when it quotes 5 or more of the 8 codes: ${label} (failure.mjs names 6/8)`,
    'adopt the package in each, pinned to a revision, and delete its copy of the vocabulary from the files named; `node ci/find-implementations.mjs --unadopted-only` lists them again',
  );

test('the_census_counts_every_restated_vocabulary_and_refuses_what_it_cannot_read', () => {
  const dir = join(root, 'target', 'real-tests', `tools-census-${process.pid}`);
  const home = join(dir, 'home');
  const product = join(dir, 'products', 'example-product');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  // A copy of the package beside the products: started with no root, it searches its parent, the case's directory.
  for (const part of ['catalogue', 'codegen', 'ci', 'js']) cpSync(join(root, part), join(dir, 'package', part), { recursive: true });
  const git = (...words) => assert.equal(spawnSync('git', ['-C', product, ...words], { env: isolated(home) }).status, 0, `git ${words.join(' ')}`);
  let files = {};
  // The product as a fresh checkout of one commit holding `committed`, its origin itself when `remote`.
  const checkout = (committed, remote) => {
    rmSync(product, { recursive: true, force: true });
    mkdirSync(product, { recursive: true });
    for (const [path, text] of Object.entries(committed)) writeFileSync(join(product, path), text);
    git('init', '-q', '-b', 'main');
    git('add', '.');
    git('-c', 'user.name=Juniper Vale', '-c', 'user.email=juniper@example.invalid', 'commit', '-q', '-m', 'the product');
    if (remote) {
      git('remote', 'add', 'origin', product);
      git('fetch', '-q', 'origin');
    }
    files = { ...committed };
  };
  const census = (words, { script = join(root, 'ci', 'find-implementations.mjs'), env = isolated(home) } = {}) => {
    const ran = spawnSync(process.execPath, [script, ...words], { cwd: dir, env, encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const untouched = (step) => {
    assert.deepEqual(filesUnder(product), files, `${step}: the product's files are left as they were`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    checkout({ 'failure.mjs': COPY }, true);
    const rows = `RESTATES  ${LABEL}  (1 file(s))\n         failure.mjs  names 6/8\n`;
    assert.deepEqual(census(['products']), { status: EXIT_FAILURE, stdout: `${rows}\n${SUMMARY(0, 1, 1, 0, 0)}${restated('products', LABEL)}`, stderr: '' });
    untouched('a product restating the vocabulary');
    assert.deepEqual(census(['products', '--unadopted-only']), { status: EXIT_FAILURE, stdout: `${rows}${SUMMARY(0, 1, 1, 0, 0)}${restated('products', LABEL)}`, stderr: '' });
    untouched('a product restating the vocabulary, unadopted only');
    const beside = `tools-census-${process.pid}/${LABEL}`;
    assert.deepEqual(census([], { script: join(dir, 'package', 'ci', 'find-implementations.mjs') }), {
      status: EXIT_FAILURE,
      stdout: `RESTATES  ${beside}  (1 file(s))\n         failure.mjs  names 6/8\n\n${SUMMARY(0, 1, 1, 0, 0)}${restated(dir, beside)}`,
      stderr: '',
    });
    untouched('no root: the parent of the package, the package left out');

    const failure = join(product, 'failure.mjs');
    chmodSync(failure, 0o000); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    const unreadable = census(['products']);
    chmodSync(failure, 0o644); // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
    assert.deepEqual(unreadable, {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        TOOLS,
        'wisent_errors.census.implementations',
        'file-unreadable',
        `reading ${failure} while counting the implementations under products: the operating system refused the read, so whether it restates the vocabulary or declares the package is unknown; observed: ${failure} is a file of 93 bytes, mode 0, owner uid ${process.getuid()}; the operating system answered EACCES: permission denied, open '${failure}'`,
        `let the user running the census read it (chmod u+r ${failure}), or name roots that leave it out`,
      ),
    });
    untouched('a file it may not read');

    assert.deepEqual(census(['products'], { env: { ...isolated(home), PATH: '' } }), {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        TOOLS,
        'wisent_errors.census.implementations',
        'git-absent',
        `asking git where ${product} came from and what its remote tip holds: no git program could be started, so a stale checkout cannot be told from a product that restates the vocabulary; observed: PATH holds ""; starting git answered spawnSync git ENOENT`,
        'install git or put it on PATH, then count again',
      ),
    });
    untouched('no git to start');

    const manifest = (pin) => JSON.stringify({ name: 'example-product', dependencies: { '@wisent/errors': `github:wisent-ai/wisent-errors${pin}` } });
    checkout({ 'package.json': manifest(`#${PIN}`), 'failure.mjs': `import { failure } from '@wisent/errors';\n${COPY}` }, true);
    assert.deepEqual(census(['products']), {
      status: EXIT_SUCCESS,
      stdout: `adopted   ${LABEL}  (1 file(s))\n  +      failure.mjs  names 6/8\n\ndeclares  ${LABEL}  pin ${PIN}\n${SUMMARY(1, 1, 0, 0, 1)}`,
      stderr: '',
    });
    untouched('a product that adopted the package');
    assert.deepEqual(census(['products', '--unadopted-only']), { status: EXIT_SUCCESS, stdout: SUMMARY(1, 1, 0, 0, 1), stderr: '' });
    untouched('a product that adopted the package, unadopted only');

    checkout({ 'package.json': manifest(''), 'failure.mjs': CLEAN }, true);
    assert.deepEqual(census(['products']), { status: EXIT_SUCCESS, stdout: `\ndeclares  ${LABEL}  pin unpinned\n${SUMMARY(1, 0, 0, 0, 0)}`, stderr: '' });
    untouched('a manifest naming no revision');

    // The remote tip no longer restates the vocabulary; the working copy still does.
    checkout({ 'failure.mjs': CLEAN }, true);
    writeFileSync(failure, COPY);
    files = { 'failure.mjs': COPY };
    assert.deepEqual(census(['products']), { status: EXIT_SUCCESS, stdout: `stale     ${LABEL}  (1 file(s))\n         failure.mjs  names 6/8\n\n${SUMMARY(0, 1, 0, 1, 0)}`, stderr: '' });
    untouched('a stale checkout');

    checkout({ 'failure.mjs': COPY }, false);
    assert.deepEqual(census(['products']), { status: EXIT_SUCCESS, stdout: `detached  ${LABEL}  (1 file(s))\n         failure.mjs  names 6/8\n\n${SUMMARY(0, 1, 0, 1, 0)}`, stderr: '' });
    untouched('a checkout with no remote');

    assert.deepEqual(census(['gone']), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.paths',
        'path-absent',
        `opening the root to search gone: nothing is at that path, so there is nothing to read and nothing could be found clean; observed: ${dir} exists and holds 3 entries: home, package, products`,
        `name the root to search as it exists; a relative path is read from ${dir}`,
      ),
    });
    untouched('a root that is not there');

    assert.deepEqual(census([`${LABEL}/failure.mjs`]), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.paths',
        'path-not-directory',
        `opening the root to search ${LABEL}/failure.mjs: the path is a file, and the root to search is read as a directory; observed: ${LABEL}/failure.mjs is a file of 93 bytes, mode 644, owner uid ${process.getuid()}`,
        `name the directory that holds it: ${product}`,
      ),
    });
    untouched('a root that is a file');

    assert.deepEqual(census(['products', '--all']), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.arguments',
        'option-unknown',
        'reading the options of ci/find-implementations.mjs: --all is not one of its options, and nothing it does reads it; observed: the words given: products --all',
        'drop --all or spell it as one of its options: node ci/find-implementations.mjs [<root>...] [--unadopted-only]',
      ),
    });
    untouched('an option it lacks');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
