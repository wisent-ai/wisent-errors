// Real test of `node tests/inventory.mjs <revision> <extended-regex>
// <path>...`, the command a defect register's revision-bound completion probe
// runs to list the lines of one committed revision that still hold a
// construct that must not remain (docs/errors/tools.md,
// `wisent_errors.inventory.list`, "Started through: `node
// tests/inventory.mjs`"; it lives under tests/ by the fleet's convention for
// such probes, and ci/check.mjs reads it as one of the package's commands).
//
//   node --test tests/tools/inventory.mjs
//
// Rule 4: the inventory is this package's own command, started here as the
// process a probe starts, with process.execPath. It reads the git
// repository it ships in, so it runs from a copy of the package
// (tests/inventory.mjs with ci/, codegen/, js/ and catalogue/) under
// target/real-tests/tools-inventory-<pid>/package, which the test makes a
// real git repository with git itself, commits notes.txt to and then edits:
// the committed revision is what the inventory lists, through the real git
// it starts. Nothing stands in for git; the inventory has no other backend.
// Rule 5: every step asserts the exit status and the whole of stdout (the
// listed lines, or nothing) and stderr (a refusal's three lines, with git's
// own status and complaint), then reads the copy's notes.txt back as the
// working copy left it (the inventory lists the commit, never the working
// copy, and writes nothing) and the case's home back empty.
// Rule 7: one test, the inventory's whole story: a copy that is no git
// repository refused, then, committed, the matching lines of the revision
// listed though the working copy no longer holds them, nothing matching
// listed as nothing, a revision git does not know, a pattern git does not
// read, no git to start, too few operands and an option it lacks, each
// refused.
// Rule 8: the inventory and git are started with the environment cleared
// and given only PATH, HOME, TMPDIR and XDG_* inside the case's home,
// GIT_CONFIG_NOSYSTEM so git reads no configuration outside the case, and
// GIT_CEILING_DIRECTORIES at the case's directory so git never climbs into
// the checkout holding it; the inventory has no backend variable of its own.
// Rule 9: every status, line and sentence below, git's complaints included,
// was copied from the inventory run by hand with `env -i` over a copy made
// and committed the same way; only the copy's path is interpolated.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '../..');
const TOOLS = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const LINT = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/lint.md';
const USAGE = 'node tests/inventory.mjs <revision> <extended-regex> <path>...';
// The statuses the inventory answered: listed, a refusal, a refusal of what it was named.
const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;
const USAGE_EXIT = 2;
const COMMITTED = 'first line\nJuniper Vale lives at example-host\n';
const EDITED = 'first line\n';

// The child's whole environment: PATH, a home, temporary directory and XDG directories inside the case, git kept inside the case.
const isolated = (dir, home) => ({
  PATH: process.env.PATH,
  HOME: home,
  TMPDIR: home,
  XDG_CONFIG_HOME: join(home, '.config'),
  XDG_CACHE_HOME: join(home, '.cache'),
  XDG_DATA_HOME: join(home, '.local', 'share'),
  XDG_STATE_HOME: join(home, '.local', 'state'),
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_CEILING_DIRECTORIES: dir,
});

// The three lines of a refusal of `operation`'s cause `id`, listed on `page`.
const refusal = (page, operation, id, sentence, remedy) => `Error: ${sentence}\nfix: ${remedy}\ncause: ${operation}.${id}; ${page}#${operation.replaceAll('.', '-')}-${id}\n`;

test('inventory_lists_a_revisions_matching_lines_or_refuses_what_git_cannot_read', () => {
  const dir = join(root, 'target', 'real-tests', `tools-inventory-${process.pid}`);
  const home = join(dir, 'home');
  const copy = join(dir, 'package');
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(home, { recursive: true });
  for (const part of ['tests/inventory.mjs', 'ci', 'codegen', 'js', 'catalogue']) cpSync(join(root, part), join(copy, part), { recursive: true });
  const env = isolated(dir, home);
  const git = (...words) => assert.equal(spawnSync('git', ['-C', copy, ...words], { env }).status, 0, `git ${words.join(' ')}`);
  const inventory = (words, withEnv = env) => {
    const ran = spawnSync(process.execPath, [join(copy, 'tests', 'inventory.mjs'), ...words], { cwd: dir, env: withEnv, encoding: 'utf8' });
    return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
  };
  const notes = join(copy, 'notes.txt');
  const holds = (step, text) => {
    assert.equal(readFileSync(notes, 'utf8'), text, `${step}: notes.txt is left as the working copy holds it`);
    assert.deepEqual(readdirSync(home), [], `${step}: nothing is written to the home`);
  };
  try {
    writeFileSync(notes, COMMITTED);
    assert.deepEqual(inventory(['HEAD', 'Juniper', 'notes.txt']), {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        TOOLS,
        'wisent_errors.inventory.list',
        'repository-not-git',
        `listing the lines of HEAD that match "Juniper": ${copy} holds no git repository, as an unpacked archive of the source does not, so no committed revision can be read; observed: git exited 128 and said fatal: not a git repository (or any of the parent directories): .git`,
        `run it in a clone of the repository, where \`git -C ${copy} log -1\` names a commit`,
      ),
    });
    holds('a copy that is no repository', COMMITTED);

    git('init', '-q', '-b', 'main');
    git('add', 'notes.txt');
    git('-c', 'user.name=Juniper Vale', '-c', 'user.email=juniper@example.invalid', 'commit', '-q', '-m', 'notes');
    // The working copy no longer holds the line; the committed revision does.
    writeFileSync(notes, EDITED);
    assert.deepEqual(inventory(['HEAD', 'Juniper', 'notes.txt']), { status: EXIT_SUCCESS, stdout: 'HEAD:notes.txt:2:Juniper Vale lives at example-host\n', stderr: '' });
    holds('the matching lines of the revision', EDITED);
    assert.deepEqual(inventory(['HEAD', 'example-guest', 'notes.txt']), { status: EXIT_SUCCESS, stdout: '', stderr: '' });
    holds('nothing matching', EDITED);

    assert.deepEqual(inventory(['no-such-revision', 'Juniper', 'notes.txt']), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        TOOLS,
        'wisent_errors.inventory.list',
        'revision-unknown',
        `listing the lines of no-such-revision that match "Juniper": git knows no revision no-such-revision in ${copy}; observed: git exited 128 and said fatal: unable to resolve revision: no-such-revision`,
        `name a commit, tag or branch the checkout holds; \`git -C ${copy} fetch\` brings one it lacks`,
      ),
    });
    holds('a revision git does not know', EDITED);

    assert.deepEqual(inventory(['HEAD', 'a(', 'notes.txt']), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        TOOLS,
        'wisent_errors.inventory.list',
        'pattern-refused',
        `listing the lines of HEAD that match "a(": git does not read "a(" as an extended regular expression; observed: git exited 128 and said fatal: -e option, 'a(': parentheses not balanced`,
        'write the pattern as a POSIX extended regular expression, escaping the characters git names',
      ),
    });
    holds('a pattern git does not read', EDITED);

    assert.deepEqual(inventory(['HEAD', 'Juniper', 'notes.txt'], { ...env, PATH: '' }), {
      status: EXIT_FAILURE,
      stdout: '',
      stderr: refusal(
        TOOLS,
        'wisent_errors.inventory.list',
        'git-absent',
        'listing the lines of HEAD that match "Juniper": no git program could be started; observed: PATH holds ""; starting git answered spawnSync git ENOENT',
        'install git or put it on PATH, then list again',
      ),
    });
    holds('no git to start', EDITED);

    assert.deepEqual(inventory(['HEAD', 'Juniper']), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.arguments',
        'operands-miscounted',
        'reading the operands of tests/inventory.mjs: it takes a revision, a pattern and at least one path and was given 2; observed: operands given: HEAD Juniper',
        `name a revision, a pattern and at least one path: ${USAGE}`,
      ),
    });
    holds('too few operands', EDITED);

    assert.deepEqual(inventory(['HEAD', 'Juniper', 'notes.txt', '--all']), {
      status: USAGE_EXIT,
      stdout: '',
      stderr: refusal(
        LINT,
        'wisent_errors.lint.arguments',
        'option-unknown',
        'reading the options of tests/inventory.mjs: --all is not one of its options, and nothing it does reads it; observed: the words given: HEAD Juniper notes.txt --all',
        `drop --all or spell it as one of its options: ${USAGE}`,
      ),
    });
    holds('an option it lacks', EDITED);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
