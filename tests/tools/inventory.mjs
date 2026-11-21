// Real tests of `node tests/inventory.mjs`: the lines of a committed revision
// that match are listed and nothing matching lists nothing; a revision git
// does not know, a pattern it does not read, no git to start, and a checkout
// that is no git repository are refused. What git says is read by asking it
// the same way, and each run's whole stdout and stderr are compared. git is
// kept off the operator's configuration by a home of the case's own.
//
//   node --test tests/tools/inventory.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { EXIT_FAILURE, EXIT_SUCCESS } from '../../ci/support/refuse.mjs';
import { USAGE_EXIT } from '../../js/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const PAGE = 'https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/tools.md';
const home = join(root, 'target', 'real-tests', 'tools-inventory', `home-${process.pid}`);
const isolated = { PATH: process.env.PATH, HOME: home, TMPDIR: home, GIT_CONFIG_NOSYSTEM: '1' };
after(() => rmSync(home, { recursive: true, force: true }));

const list = (words, { at = root, env = isolated } = {}) => {
  mkdirSync(home, { recursive: true });
  const ran = spawnSync(process.execPath, [join(at, 'tests', 'inventory.mjs'), ...words], { encoding: 'utf8', env });
  return { status: ran.status, stdout: ran.stdout, stderr: ran.stderr };
};

// What git answers the grep the inventory runs in `at`: its status and its complaint.
function asked(at, [revision, pattern, ...paths], env = isolated) {
  const ran = spawnSync('git', ['-C', at, 'grep', '-n', '-E', '-e', pattern, revision, '--', ...paths], { encoding: 'utf8', env });
  return { status: ran.status, said: ran.stderr.trim() };
}

// The whole run of a refusal of the inventory's cause `id`.
const refused = (status, id, sentence, remedy) => ({
  status,
  stdout: '',
  stderr: `Error: ${sentence}\nfix: ${remedy}\ncause: wisent_errors.inventory.list.${id}; ${PAGE}#wisent_errors-inventory-list-${id}\n`,
});

// A copy of the inventory and what it imports under the ignored target/, `body(copy)` run on it.
function inCopy(name, body) {
  const copy = join(root, 'target', 'real-tests', 'tools-inventory', `${name}-${process.pid}`);
  rmSync(copy, { recursive: true, force: true });
  mkdirSync(copy, { recursive: true });
  try {
    for (const part of ['tests', 'ci', 'codegen', 'js', 'catalogue']) cpSync(join(root, part), join(copy, part), { recursive: true });
    return body(copy);
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
}

test('the_matching_lines_of_the_committed_revision_are_listed', () => {
  inCopy('listed', (copy) => {
    const git = (...words) => assert.equal(spawnSync('git', ['-C', copy, ...words], { env: isolated }).status, 0, `git ${words.join(' ')}`);
    mkdirSync(home, { recursive: true });
    writeFileSync(join(copy, 'notes.txt'), 'first line\nJuniper Vale lives at example-host\n');
    git('init', '-q', '-b', 'main');
    git('add', 'notes.txt');
    git('-c', 'user.name=Juniper Vale', '-c', 'user.email=juniper@example.invalid', 'commit', '-q', '-m', 'notes');
    // The working copy no longer holds the line; the committed revision does.
    writeFileSync(join(copy, 'notes.txt'), 'first line\n');
    assert.deepEqual(list(['HEAD', 'Juniper', 'notes.txt'], { at: copy }), { status: EXIT_SUCCESS, stdout: 'HEAD:notes.txt:2:Juniper Vale lives at example-host\n', stderr: '' });
    assert.deepEqual(list(['HEAD', 'example-guest', 'notes.txt'], { at: copy }), { status: EXIT_SUCCESS, stdout: '', stderr: '' });
  });
});

test('an_unknown_revision_is_refused', () => {
  const words = ['no-such-revision', 'x', 'README.md'];
  const git = asked(root, words);
  assert.deepEqual(
    list(words),
    refused(
      USAGE_EXIT,
      'revision-unknown',
      `listing the lines of no-such-revision that match "x": git knows no revision no-such-revision in ${root}; observed: git exited ${git.status} and said ${git.said}`,
      `name a commit, tag or branch the checkout holds; \`git -C ${root} fetch\` brings one it lacks`,
    ),
  );
});

test('a_pattern_git_refuses_is_refused', () => {
  const words = ['HEAD', 'a(', 'README.md'];
  const git = asked(root, words);
  assert.deepEqual(
    list(words),
    refused(
      USAGE_EXIT,
      'pattern-refused',
      `listing the lines of HEAD that match "a(": git does not read "a(" as an extended regular expression; observed: git exited ${git.status} and said ${git.said}`,
      'write the pattern as a POSIX extended regular expression, escaping the characters git names',
    ),
  );
});

test('a_listing_without_git_is_refused', () => {
  const started = spawnSync('git', ['--version'], { env: { PATH: '' } });
  assert.notEqual(started.error, undefined, 'git cannot be started with an empty PATH');
  assert.deepEqual(
    list(['HEAD', 'x', 'README.md'], { env: { PATH: '' } }),
    refused(
      EXIT_FAILURE,
      'git-absent',
      `listing the lines of HEAD that match "x": no git program could be started; observed: PATH holds ""; starting git answered ${started.error.message}`,
      'install git or put it on PATH, then list again',
    ),
  );
});

test('a_listing_outside_a_repository_is_refused', () => {
  inCopy('outside', (copy) => {
    const env = { ...isolated, GIT_CEILING_DIRECTORIES: resolve(copy, '..') };
    const words = ['HEAD', 'x', 'README.md'];
    const git = asked(copy, words, env);
    assert.deepEqual(
      list(words, { at: copy, env }),
      refused(
        EXIT_FAILURE,
        'repository-not-git',
        `listing the lines of HEAD that match "x": ${copy} holds no git repository, as an unpacked archive of the source does not, so no committed revision can be read; observed: git exited ${git.status} and said ${git.said}`,
        `run it in a clone of the repository, where \`git -C ${copy} log -1\` names a commit`,
      ),
    );
  });
});
