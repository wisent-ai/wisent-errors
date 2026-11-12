#!/usr/bin/env node
// Refuse a hand-built failure envelope in a consuming repository.
//
// The point of one package is that `failure_point` and `error_code` come from it
// and nowhere else. A product that writes those keys into a string literal has
// forked the contract without saying so, which is precisely how six copies came
// to exist and one of them lost the vocabulary while five kept it.
//
// This is the guard consumers run, not this package: point it at a source tree.
//
// It reports sites, not verdicts. A line that merely declares a field or reads
// another vendor's `error_code` is a false positive, and the guard says so rather
// than asserting a defect it has not established -- an earlier version accused
// stado's Azure role-assignment parser of hand-building our envelope.
//
// Usage: node ci/no-handrolled-envelope.mjs <path> [<path>...]
//
// It reports the exact lines, because a guard that says only "something is
// wrong" is a guard people learn to skip.

import { statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { Words } from './arguments.mjs';
import { listDirectory, openDirectory, packageSource, parentOf, readTreeFile } from './input.mjs';
import { exitOf, guarded, refuse, refusalText } from './refuse.mjs';

const USAGE = 'node ci/no-handrolled-envelope.mjs <path> [<path>...]';
const SOURCE = new Set(['.rs', '.py', '.mjs', '.js', '.ts', '.tsx', '.jsx', '.go', '.swift', '.sh']);
const SKIP = new Set(['node_modules', 'target', '.git', 'dist', 'build', '.venv', '__pycache__', 'vendor']);
// This package is where these keys belong, so its own source is never read
// (packageSource): a guard that accuses its own source is a guard nobody runs
// twice.
// Quoted or bare, key or assignment: the copies in this fleet are written both
// ways, and a guard that only knows one spelling reports a clean tree.
const KEYS = /(["']?)(failure_point|error_code)\1\s*[:=]/;
const findings = [];
let files = 0;

function walk(path) {
  for (const entry of listDirectory(path, 'a directory of the tree')) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) {
      if (!SKIP.has(entry.name)) walk(child);
    } else if (entry.isFile()) {
      read(child);
    }
  }
}

function read(path) {
  if (!SOURCE.has(extname(path)) || packageSource(path)) return;
  files += 1;
  readTreeFile(path, 'a source file').split('\n').forEach((line, index) => {
    if (KEYS.test(line)) findings.push(`${path}:${index + 1}  ${line.trim().slice(0, 120)}`);
  });
}

process.exitCode = guarded(() => {
  const roots = new Words('ci/no-handrolled-envelope.mjs', USAGE, process.argv.slice(2)).operands('at least one path', (count) => count > 0);
  for (const root of roots) {
    let entry;
    try {
      entry = statSync(root);
    } catch (error) {
      if (error.code === 'ENOENT') refuse('wisent_errors.lint.paths', 'path-absent', { what: 'the tree', path: root, parent: parentOf(root), cwd: process.cwd() });
      openDirectory(root, 'the tree');
    }
    if (entry.isDirectory()) walk(root);
    else read(root);
  }
  if (findings.length === 0) {
    console.log(`no hand-built envelope in ${files} source file(s) under ${roots.join(', ')}`);
    return 0;
  }
  console.log(refusalText('wisent_errors.lint.handrolled', 'envelope-key-written', { files: String(files), roots: roots.join(', '), count: String(findings.length), sites: `${findings.length} line(s) below` }));
  for (const finding of findings) console.log(`  ${finding}`);
  console.log(
    '\nEach needs a reason. Building an envelope here means the derived fields can be' +
      '\nwrong, so build it with wisent-errors instead. Three answers are legitimate and' +
      '\ncommon: an operator-visible log line whose format is already parsed, a field' +
      "\ndeclaration, and another API's own `error_code` -- Azure has one, and this guard" +
      '\ncannot tell it from ours. Read the line before believing the count.',
  );
  return exitOf('wisent_errors.lint.handrolled', 'envelope-key-written');
});
