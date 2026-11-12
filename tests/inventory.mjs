#!/usr/bin/env node
// Lists the source lines of one committed revision that match a pattern, for
// a defect register's revision-bound completion probe of a construct that
// must not remain:
//
//   node tests/inventory.mjs <revision> <extended-regex> <path>...
//
// Standard output carries one `revision:path:line:text` per remaining
// instance and is empty when none remains. git grep's own "nothing matched"
// is the empty answer; every other answer of git is a declared cause of
// `wisent_errors.inventory.list`: a revision git does not know, a pattern it
// does not read, or no git to ask.
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { Words } from '../ci/arguments.mjs';
import { guarded, refuse } from '../ci/refuse.mjs';

const root = resolve(import.meta.dirname, '..');
const LIST = 'wisent_errors.inventory.list';

guarded(() => {
  const words = new Words('tests/inventory.mjs', 'node tests/inventory.mjs <revision> <extended-regex> <path>...', process.argv.slice(2));
  const [revision, pattern, ...paths] = words.operands('a revision, a pattern and at least one path', (count) => count >= 3);
  // git's answer goes straight to this process's standard output, so an
  // inventory of any size is passed on whole instead of filling a buffer that
  // ends the child; only git's own complaint is kept to report a failure.
  const found = spawnSync('git', ['-C', root, 'grep', '-n', '-E', '-e', pattern, revision, '--', ...paths], {
    encoding: 'utf8',
    stdio: ['ignore', 'inherit', 'pipe'],
  });
  const values = { revision, quoted_pattern: JSON.stringify(pattern), repository: root, status: String(found.status), stderr: (found.stderr ?? '').trim() };
  if (found.error) refuse(LIST, 'git-absent', { ...values, path_variable: process.env.PATH ?? '(unset)', error: found.error.message });
  // git grep exits 1 with nothing on standard error when nothing matched
  // (https://git-scm.com/docs/git-grep#_exit_status); a complaint is git
  // refusing the revision or the pattern.
  if (!found.stderr) return;
  if (/not a git repository/i.test(found.stderr)) refuse(LIST, 'repository-not-git', values);
  if (/unable to resolve revision|bad revision|unknown revision/i.test(found.stderr)) refuse(LIST, 'revision-unknown', values);
  refuse(LIST, 'pattern-refused', values);
});
