#!/usr/bin/env node
// Find every implementation of this envelope in a tree, adopted or not.
//
// This exists because I answered "everything is migrated" three times from a list
// I had written, and was wrong three times. Each search axis found a different
// subset: the first list came from reading, the second from grepping
// `failure_point`, and the third from grepping `infra_down` — which found six more
// products, because a copy need not use the field name but must contain the
// vocabulary.
//
// So the check keys on the thing an implementation cannot avoid: the codes
// themselves. A file naming three or more of the seven is a candidate, and the
// only question left is whether its repository depends on the package or restates
// it.
//
// Two passes, because they answer two different questions and one cannot answer the
// other. The literal scan finds files that restate the vocabulary; a fully migrated
// consumer quotes no codes at all, so it produces no row and is invisible to that
// pass -- which is correct for the gate and useless for counting adopters. The
// manifest sweep answers "who depends on this" by reading the dependency files.
// weles-web-blog is the proof case: perfectly migrated, zero rows, and the earlier
// version of this tool would have counted it as neither.
//
// What neither pass can find, stated so nobody trusts the tool further than it
// goes: a module that generates or interpolates the code strings instead of writing
// them. Every implementation in this fleet spelled them out verbatim -- which is
// also where the copies did not drift -- but a future one need not.
//
// Usage: node ci/find-implementations.mjs [<root>...]     default: the parent of
//                                                         this repository
//        node ci/find-implementations.mjs --unadopted-only

import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = resolve(HERE, '..');

const args = process.argv.slice(2);
const unadoptedOnly = args.includes('--unadopted-only');
const roots = args.filter((argument) => !argument.startsWith('--'));
if (roots.length === 0) roots.push(resolve(PACKAGE_ROOT, '..'));

const CODES = JSON.parse(readFileSync(join(PACKAGE_ROOT, 'catalogue', 'codes.json'), 'utf8')).codes.map(
  (entry) => entry.code,
);
// Calibration, not taste. A first attempt asked for three of the seven and
// reported 541 repositories, because `config`, `auth`, `timeout` and `unknown` are
// ordinary tokens in any codebase -- it matched minified Next.js chunks. The
// discriminator is the one code that is not an English phrase: a file that says
// `infra_down` is talking about this taxonomy and nothing else. Requiring it plus
// a majority of the rest reproduces exactly the nineteen implementations found by
// hand, and nothing else.
const DISCRIMINATOR = 'infra_down';
const THRESHOLD = 4;

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
    } catch {
      // keep walking
    }
    current = dirname(current);
  }
  return dirname(path);
}

function walk(path) {
  let entry;
  try {
    entry = statSync(path);
  } catch {
    return;
  }
  if (entry.isDirectory()) {
    for (const child of readdirSync(path)) {
      if (SKIP.has(child)) continue;
      walk(join(path, child));
    }
    return;
  }
  const name = path.slice(path.lastIndexOf('/') + 1);
  if (MANIFESTS.has(name) && !resolve(path).startsWith(PACKAGE_ROOT)) {
    let manifest;
    try {
      manifest = readFileSync(path, 'utf8');
    } catch {
      manifest = '';
    }
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
        if (sha) pins.add(sha[0].slice(0, 8));
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

  let body;
  try {
    body = readFileSync(path, 'utf8');
  } catch {
    return;
  }
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
    try {
      const body = execFileSync('git', ['-C', repo, 'show', `${ref}:${relative_path}`], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        maxBuffer: 8 * 1024 * 1024,
      });
      if (!quoted(body, DISCRIMINATOR)) return false;
      return CODES.filter((code) => quoted(body, code)).length >= THRESHOLD;
    } catch {
      // try the next ref
    }
  }
  return null; // no remote, or the path is absent there
}

function remoteOf(repo) {
  try {
    return execFileSync('git', ['-C', repo, 'remote', 'get-url', 'origin'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
      .trim()
      .replace(/\.git$/, '')
      .toLowerCase();
  } catch {
    return null;
  }
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
    `\n${rows.length} still quote four or more codes as literals: ` +
    `${live.length} restate the taxonomy, ` +
    `${stale} are stale or detached copies of one that does not, ` +
    `${rows.length - unadopted.length} are part-migrated and name the package too.`,
);
process.exit(live.length === 0 ? 0 : 1);
