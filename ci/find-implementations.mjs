#!/usr/bin/env node
// Find every implementation of this envelope in a tree, adopted or not.
//
// Two passes: a literal scan for files that restate the vocabulary, and a
// manifest sweep for repositories that declare a dependency on the package.
// Why it keys on the codes, what neither pass can find, and how the
// thresholds below were calibrated are in docs/finding-implementations.md.
//
// Usage: node ci/find-implementations.mjs [<root>...]     default: the parent of
//                                                         this repository
//        node ci/find-implementations.mjs --unadopted-only

import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Words } from './arguments.mjs';
import { describe, listDirectory, openDirectory, readJsonInput, stateOf } from './input.mjs';
import { exitOf, guarded, refuse, refusalText } from './refuse.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = resolve(HERE, '..');
const CENSUS = 'wisent_errors.census.implementations';

const words = new Words('ci/find-implementations.mjs', 'node ci/find-implementations.mjs [<root>...] [--unadopted-only]', process.argv.slice(2));
const unadoptedOnly = words.flag('--unadopted-only');
const roots = [...words.operands('any number of roots to search', () => true)];
if (roots.length === 0) roots.push(resolve(PACKAGE_ROOT, '..'));
guarded(() => roots.forEach((root) => openDirectory(root, 'the root to search')));

const CODES = readJsonInput(join(PACKAGE_ROOT, 'catalogue', 'codes.json'), 'the vocabulary', 'an object with a list of codes', (value) =>
  Array.isArray(value?.codes) ? null : describe(value),
).codes.map((entry) => entry.code);

/** One file of the tree, refused when it cannot be read: unread, it would be counted as neither copy nor adopter. */
function readCounted(path) {
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    return refuse(CENSUS, 'file-unreadable', { path, roots: roots.join(', '), state: stateOf(path), error: error.message });
  }
}

/** git's answer, or null when git answered that it has none; a git that cannot start is refused. */
function git(repository, words) {
  try {
    return execFileSync('git', ['-C', repository, ...words], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: Infinity });
  } catch (error) {
    if (error.code === 'ENOENT') refuse(CENSUS, 'git-absent', { repository, path_variable: process.env.PATH ?? '(unset)', error: error.message });
    return null;
  }
}
// Calibration, not taste. A first attempt asked for three of the seven and
// reported 541 repositories, because `config`, `auth`, `timeout` and `unknown` are
// ordinary tokens in any codebase -- it matched minified Next.js chunks. The
// discriminator is the one code that is not an English phrase: a file that says
// `infra_down` is talking about this taxonomy and nothing else. Requiring it
// among a majority of the catalogue's codes reproduces exactly the nineteen
// implementations found by hand, and nothing else.
const DISCRIMINATOR = 'infra_down';
const THRESHOLD = Math.floor(CODES.length / 2) + 1;

// Quoted, or it does not count. Unquoted `config`, `auth`, `timeout` and
// `unknown` are ordinary tokens: counting them made `probierz/agent/stado.mjs`
// look like a copy when its only mention of the vocabulary is a prose comment,
// and made `skarbiec-hub` look like one when it emits a single literal into its
// own error field. An implementation writes the codes as strings.
const quoted = (body, code) =>
  body.includes(`'${code}'`) || body.includes(`"${code}"`) || body.includes(`\`${code}\``);

const SOURCE = new Set(['.rs', '.py', '.mjs', '.js', '.ts', '.tsx', '.jsx', '.go', '.swift', '.kt', '.java']);
const SKIP = new Set([
  'node_modules',
  'target',
  '.git',
  '.build',
  'dist',
  'build',
  '.next',
  '.vercel',
  '.turbo',
  'out',
  'coverage',
  '.venv',
  '__pycache__',
  'vendor',
  'Pods',
  'DerivedData',
  // Other checkouts of a repository are not other consumers. This fleet keeps
  // worktrees, bulk clones and superseded copies on disk, and counting them as
  // products is how a census of 13 reads as 37.
  '.worktrees',
]);
// How each ecosystem spells a dependency on this package.
const ADOPTED = /wisent-errors|wisent_errors|WisentErrors|@wisent\/errors/;

const repos = new Map();
const adopters = new Map();

// The dependency files each ecosystem declares in.
const MANIFESTS = new Set([
  'package.json',
  'Cargo.toml',
  'Package.swift',
  'pyproject.toml',
  'setup.py',
  'requirements.txt',
]);

function repoOf(path) {
  // The nearest ancestor holding a .git, else the first path segment under a root.
  let current = dirname(path);
  while (current.length > 1) {
    try {
      if (statSync(join(current, '.git')).isDirectory() || statSync(join(current, '.git')).isFile()) return current;
    } catch (error) {
      // No .git here: the walk goes on to the parent. One that cannot be
      // read is refused, never taken as no repository.
      if (error.code !== 'ENOENT') refuse(CENSUS, 'file-unreadable', { path: join(current, '.git'), roots: roots.join(', '), state: stateOf(join(current, '.git')), error: error.message });
    }
    current = dirname(current);
  }
  return dirname(path);
}

function walk(path) {
  let entry;
  try {
    entry = statSync(path);
  } catch (error) {
    // An entry that vanished between its directory's listing and this read
    // holds nothing to count; one that cannot be read is refused by name.
    if (error.code !== 'ENOENT') refuse(CENSUS, 'file-unreadable', { path, roots: roots.join(', '), state: stateOf(path), error: error.message });
    return;
  }
  if (entry.isDirectory()) {
    for (const child of listDirectory(path, 'a directory under the root')) {
      if (SKIP.has(child.name)) continue;
      walk(join(path, child.name));
    }
    return;
  }
  const name = path.slice(path.lastIndexOf('/') + 1);
  if (MANIFESTS.has(name) && !resolve(path).startsWith(PACKAGE_ROOT)) {
    const manifest = readCounted(path);
    if (ADOPTED.test(manifest)) {
      const repo = repoOf(path);
      // Read the sha out of the entry that names this package, not out of the
      // file: a manifest holds other git dependencies, and taking the first
      // 40-hex reported one product as pinned to its onboarding client and
      // another as pinned to a sha this package never had.
      // A window of characters after the name, not a line: SwiftPM puts `url:` and
      // `revision:` on separate lines and a Python requirement is split across two
      // implicitly concatenated strings, so line matching reported five pinned
      // consumers as unpinned. Third iteration of this one extraction bug -- each
      // earlier version looked right against the manifests that happened to be on
      // one line.
      const pins = new Set();
      const spelling = /wisent-errors|wisent_errors|WisentErrors|@wisent\/errors/g;
      for (let hit = spelling.exec(manifest); hit; hit = spelling.exec(manifest)) {
        const sha = manifest.slice(hit.index, hit.index + 240).match(/[0-9a-f]{40}/);
        if (sha) pins.add(sha[0]);
      }
      // A workspace inheritance -- `{ workspace = true }` -- carries no sha and is
      // pinned by the workspace manifest, which this sweep reads separately.
      if (pins.size === 0 && !/workspace\s*=\s*true/.test(manifest)) pins.add('unpinned');
      if (!adopters.has(repo)) adopters.set(repo, new Set());
      for (const pin of pins) adopters.get(repo).add(pin);
    }
  }
  if (!SOURCE.has(extname(path))) return;
  if (resolve(path).startsWith(PACKAGE_ROOT)) return;

  const body = readCounted(path);
  if (!quoted(body, DISCRIMINATOR)) return;
  const named = CODES.filter((code) => quoted(body, code));
  if (named.length < THRESHOLD) return;

  const repo = repoOf(path);
  if (!repos.has(repo)) repos.set(repo, { files: [], adopted: false });
  const record = repos.get(repo);
  record.files.push({ path, named: named.length, adopted: ADOPTED.test(body) });
  if (ADOPTED.test(body)) record.adopted = true;
}

for (const root of roots) walk(resolve(root));

// One repository is one remote, not one directory. Two checkouts of the same
// remote are two working copies of one product, and this fleet has several --
// counting them separately is what made an earlier count of thirteen read as
// thirty-seven.
/// Whether the same file still restates the vocabulary at the remote tip.
///
/// A local checkout can be stale: this fleet keeps bulk clones and old worktrees,
/// and one of them is four months behind a product that has already migrated.
/// Reading the file out of `origin/HEAD` is the difference between "this product
/// restates the taxonomy" and "this directory is out of date", which are opposite
/// findings about the same bytes.
function restatesAtRemote(repo, relative_path) {
  for (const ref of ['origin/HEAD', 'origin/main', 'origin/master']) {
    const body = git(repo, ['show', `${ref}:${relative_path}`]);
    if (body === null) continue;
    if (!quoted(body, DISCRIMINATOR)) return false;
    return CODES.filter((code) => quoted(body, code)).length >= THRESHOLD;
  }
  return null; // no remote, or the path is absent there
}

function remoteOf(repo) {
  const url = git(repo, ['remote', 'get-url', 'origin']);
  return url === null ? null : url.trim().replace(/\.git$/, '').toLowerCase();
}

const byRemote = new Map();
for (const [repo, record] of repos) {
  const key = remoteOf(repo) ?? repo;
  const existing = byRemote.get(key);
  if (!existing) {
    byRemote.set(key, { repo, record, copies: 1 });
    continue;
  }
  existing.copies += 1;
  // Prefer the checkout that has adopted: the others are stale copies of it.
  if (record.adopted && !existing.record.adopted) {
    existing.repo = repo;
    existing.record = record;
  }
}

// A repository counts as adopted when any of its candidate files names the
// package: the derivation may sit in one file the others import.
const rows = [...byRemote.values()]
  .map((entry) => [entry.repo, { ...entry.record, copies: entry.copies }])
  .sort((left, right) => left[0].localeCompare(right[0]));
let unadopted = rows.filter(([, record]) => !record.adopted);

for (const [repo, record] of rows) {
  if (!record.adopted) {
    const live = record.files.map((file) => restatesAtRemote(repo, relative(repo, file.path)));
    if (live.every((answer) => answer === false)) {
      record.stale = true;
    } else if (live.every((answer) => answer === null)) {
      record.detached = true;
    }
  }
  if (unadoptedOnly && record.adopted) continue;
  const label = record.adopted
    ? 'adopted '
    : record.stale
      ? 'stale   '
      : record.detached
        ? 'detached'
        : 'RESTATES';
  const copies = record.copies > 1 ? `, ${record.copies} checkouts` : '';
  console.log(
    `${label}  ${relative(resolve(roots[0], '..'), repo) || repo}  (${record.files.length} file(s)${copies})`,
  );
  for (const file of record.files) {
    const mark = file.adopted ? '  +' : '   ';
    console.log(`${mark}      ${relative(repo, file.path)}  names ${file.named}/${CODES.length}`);
  }
}

// A stale checkout of a migrated product, and a worktree with no remote, are not
// products restating the taxonomy. Only a live one counts against the census.
const live = unadopted.filter(([, record]) => !record.stale && !record.detached);
const stale = unadopted.length - live.length;
const declared = [...adopters.entries()].sort((left, right) => left[0].localeCompare(right[0]));
if (!unadoptedOnly) {
  console.log('');
  for (const [repo, pins] of declared) {
    console.log(`declares  ${relative(resolve(roots[0], '..'), repo) || repo}  pin ${[...pins].join(', ')}`);
  }
}

console.log(
  `\n${declared.length} checkout(s) declare a dependency on the package.` +
    `\n${rows.length} still quote ${THRESHOLD} or more codes as literals: ` +
    `${live.length} restate the taxonomy, ` +
    `${stale} are stale or detached copies of one that does not, ` +
    `${rows.length - unadopted.length} are part-migrated and name the package too.`,
);
if (live.length > 0) {
  const repositories = live
    .map(([repo, record]) => `${relative(resolve(roots[0], '..'), repo) || repo} (${record.files.map((file) => `${relative(repo, file.path)} names ${file.named}/${CODES.length}`).join(', ')})`)
    .join('; ');
  console.log(refusalText(CENSUS, 'vocabulary-restated', { roots: roots.join(', '), count: String(live.length), threshold: String(THRESHOLD), codes: String(CODES.length), repositories }));
  process.exitCode = exitOf(CENSUS, 'vocabulary-restated');
}
