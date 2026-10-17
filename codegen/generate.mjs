#!/usr/bin/env node
// Turn the catalogue into one generated module per language.
//
// The catalogue is the source of truth and this is the only thing allowed to
// read it at build time. Every runtime gets the same table, so a code's meaning
// cannot drift between languages -- which is exactly what happened when six
// products each kept their own copy and one of them quietly lost the vocabulary.
//
// Generated files are committed. A consumer needs no build step, and CI
// regenerates and fails on any difference, so the copies stay copies.
//
// Usage: node codegen/generate.mjs [--check]

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rust } from './rust.mjs';
import { python } from './python.mjs';
import { javascript } from './javascript.mjs';
import { swift } from './swift.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CATALOGUE = join(ROOT, 'catalogue', 'codes.json');
const CHECK = process.argv.includes('--check');

const catalogue = JSON.parse(readFileSync(CATALOGUE, 'utf8'));
const banner = (comment) => [
  `${comment} Generated from catalogue/codes.json by codegen/generate.mjs.`,
  `${comment} Do not edit: change the catalogue and regenerate.`,
  `${comment} catalogue version ${catalogue.version}`,
].join('\n');

const codes = catalogue.codes;
const exact = Object.entries(catalogue.upstream_status.exact).map(([status, code]) => [Number(status), code]);
const ranges = catalogue.upstream_status.ranges;
const fallback = catalogue.upstream_status.default;
const context = { catalogue, codes, exact, ranges, fallback, banner };

// The Rust module is what rustfmt makes of it, run in the crate under the
// edition rust/Cargo.toml declares, so the push gate's `cargo fmt --check`
// and this generator agree on the same bytes. A manifest without an edition,
// or a rustfmt that cannot run or refuses the module, ends the generation
// with the cause.
const CRATE_MANIFEST = join(ROOT, 'rust', 'Cargo.toml');
function crateEdition() {
  const declared = readFileSync(CRATE_MANIFEST, 'utf8').match(/^edition\s*=\s*"([^"]+)"/m);
  if (!declared) throw new Error(`${CRATE_MANIFEST} declares no edition for rustfmt to format under`);
  return declared[1];
}

function rustfmt(body, path) {
  const edition = crateEdition();
  console.log(`formatting ${path.slice(ROOT.length + 1)} with rustfmt --edition ${edition}`);
  return execFileSync('rustfmt', ['--edition', edition], { input: body, encoding: 'utf8', cwd: dirname(path) });
}

const rustModule = join(ROOT, 'rust', 'src', 'codes.rs');
const targets = [
  { path: rustModule, body: rustfmt(rust(context), rustModule) },
  { path: join(ROOT, 'python', 'wisent_errors', 'codes.py'), body: python(context) },
  { path: join(ROOT, 'js', 'codes.mjs'), body: javascript(context) },
  { path: join(ROOT, 'swift', 'Sources', 'WisentErrors', 'Codes.swift'), body: swift(context) },
];

let drifted = false;
for (const target of targets) {
  mkdirSync(dirname(target.path), { recursive: true });
  // A target not generated yet is absent; any other read failure ends the
  // generation rather than being overwritten blind.
  let existing = null;
  try {
    existing = readFileSync(target.path, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (existing === target.body) {
    console.log(`unchanged  ${target.path.slice(ROOT.length + 1)}`);
    continue;
  }
  if (CHECK) {
    drifted = true;
    console.log(`DRIFTED    ${target.path.slice(ROOT.length + 1)}`);
    continue;
  }
  writeFileSync(target.path, target.body);
  console.log(`written    ${target.path.slice(ROOT.length + 1)}`);
}

if (CHECK && drifted) {
  console.log('\ngenerated code does not match the catalogue; run codegen/generate.mjs');
  process.exit(1);
}
