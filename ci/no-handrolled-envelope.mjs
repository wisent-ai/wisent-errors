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

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOTS = process.argv.slice(2);
if (ROOTS.length === 0) {
  console.log('usage: node ci/no-handrolled-envelope.mjs <path> [<path>...]');
  process.exit(2);
}

const SOURCE = new Set(['.rs', '.py', '.mjs', '.js', '.ts', '.tsx', '.jsx', '.go', '.swift', '.sh']);
const SKIP = new Set(['node_modules', 'target', '.git', 'dist', 'build', '.venv', '__pycache__', 'vendor']);
// This package is where these keys belong. Matched by resolved root rather than
// by name in the path: a relative invocation has no name in it, and a guard that
// accuses its own source is a guard nobody runs twice.
const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
// Quoted or bare, key or assignment: the copies in this fleet are written both
// ways, and a guard that only knows one spelling reports a clean tree.
const KEYS = /(["']?)(failure_point|error_code)\1\s*[:=]/;
const findings = [];

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
  if (!SOURCE.has(extname(path)) || resolve(path).startsWith(PACKAGE_ROOT)) return;

  const lines = readFileSync(path, 'utf8').split('\n');
  lines.forEach((line, index) => {
    if (KEYS.test(line)) findings.push(`${path}:${index + 1}  ${line.trim().slice(0, 120)}`);
  });
}

for (const root of ROOTS) walk(root);

if (findings.length === 0) {
  console.log(`no hand-built envelope in ${ROOTS.join(', ')}`);
  process.exit(0);
}

console.log(`${findings.length} site(s) name an envelope key outside the package:`);
for (const finding of findings) console.log(`  ${finding}`);
console.log(
  '\nEach needs a reason. Building an envelope here means the derived fields can be' +
    '\nwrong, so build it with wisent-errors instead. Three answers are legitimate and' +
    '\ncommon: an operator-visible log line whose format is already parsed, a field' +
    "\ndeclaration, and another API's own `error_code` -- Azure has one, and this guard" +
    '\ncannot tell it from ours. Read the line before believing the count.',
);
process.exit(1);
