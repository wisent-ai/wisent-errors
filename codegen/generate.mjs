#!/usr/bin/env node
// Turn the catalogue into the generated modules of every runtime.
//
// catalogue/codes.json is the vocabulary, catalogue/declaration.json the rules
// a declared cause or warning is held to, and catalogue/failures/ this
// package's own failures, one part per area. This is the only thing allowed to
// read them at build time. Every runtime gets the same tables, so a code's
// meaning, a declaration rule or one of this package's own refusals cannot
// drift between languages -- which is exactly what happened when six products
// each kept their own copy and one of them quietly lost the vocabulary.
//
// Generated files are committed. A consumer needs no build step, and CI
// regenerates and fails on any difference, so the copies stay copies.
//
// Usage: node codegen/generate.mjs [--check]

import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rust } from './rust.mjs';
import { python } from './python.mjs';
import { javascript } from './javascript.mjs';
import { swift } from './swift.mjs';
import { declarationJs, declarationPython, declarationRust, declarationSwift } from './declaration.mjs';
import { byArea, failuresJs, failuresPython, failuresRust, failuresRustModule, failuresSwift, failuresSwiftNamespace, rustModule, swiftFile } from './failures.mjs';
import { pages } from './pages.mjs';
import { PARTS, operationsFor, readParts } from './parts.mjs';
import { guarded, refuse } from '../ci/refuse.mjs';
import { holding, listDirectory, readJsonInput, stateOf } from '../ci/input.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CHECK = process.argv.includes('--check');
const GENERATE = 'wisent_errors.codegen.generate';

const catalogue = readJsonInput(join(ROOT, 'catalogue', 'codes.json'), 'the vocabulary', 'an object with codes, severities, upstream_status, exit_code, generic_sentences and failure_point', holding('codes', 'severities', 'upstream_status', 'exit_code', 'generic_sentences', 'failure_point'));
const declaration = readJsonInput(join(ROOT, 'catalogue', 'declaration.json'), 'the declaration rules', 'an object with placeholder, raw_message, cause_id, test_path, fields and sentences', holding('placeholder', 'raw_message', 'cause_id', 'test_path', 'fields', 'sentences'));
const parts = guarded(() => readParts());
const banner = (comment, source = 'catalogue/codes.json') => [
  `${comment} Generated from ${source} by codegen/generate.mjs.`,
  `${comment} Do not edit: change the catalogue and regenerate.`,
  `${comment} catalogue version ${catalogue.version}`,
].join('\n');

const codes = catalogue.codes;
const exact = Object.entries(catalogue.upstream_status.exact).map(([status, code]) => [Number(status), code]);
const ranges = catalogue.upstream_status.ranges;
const fallback = catalogue.upstream_status.default;
const context = { catalogue, codes, exact, ranges, fallback, banner, declaration };
const own = (runtime) => ({ banner, operations: guarded(() => operationsFor(runtime, parts)) });
// Rust and Swift get one module per part (codegen/failures.mjs).
const areas = (runtime) => byArea(own(runtime).operations, parts);

const at = (...segments) => join(ROOT, ...segments);
const rustFailures = (name) => at('rust', 'src', 'failures', name);
// The generated Swift: the catalogue's codes and declaration rules beside the
// hand-written catalogue types, and every part's own causes in `Own/`.
const swiftFailures = (name) => at('swift', 'Sources', 'WisentErrors', 'Own', name);
const rustAreas = areas('rust');
const swiftAreas = areas('swift');
const targets = [
  { path: at('rust', 'src', 'codes.rs'), body: rust(context) },
  { path: at('rust', 'src', 'declaration.rs'), body: declarationRust(context) },
  { path: rustFailures('mod.rs'), body: failuresRustModule(rustAreas, banner) },
  ...rustAreas.map((area) => {
    const path = rustFailures(`${rustModule(area.area)}.rs`);
    return { path, body: failuresRust(area, banner) };
  }),
  { path: at('python', 'wisent_errors', 'codes.py'), body: python(context) },
  { path: at('python', 'wisent_errors', 'declaration.py'), body: declarationPython(context) },
  { path: at('python', 'wisent_errors', 'failures.py'), body: failuresPython(own('python')) },
  { path: at('js', 'codes.mjs'), body: javascript(context) },
  { path: at('js', 'declaration.mjs'), body: declarationJs(context) },
  { path: at('js', 'failures.mjs'), body: failuresJs(own('js')) },
  { path: at('swift', 'Sources', 'WisentErrors', 'Catalogue', 'Codes.swift'), body: swift(context) },
  { path: at('swift', 'Sources', 'WisentErrors', 'Catalogue', 'Declaration.swift'), body: declarationSwift(context) },
  { path: swiftFailures('OwnFailures.swift'), body: failuresSwiftNamespace(swiftAreas, banner) },
  ...swiftAreas.map((area) => ({ path: swiftFailures(swiftFile(area.area)), body: failuresSwift(area, banner) })),
  ...pages(parts, PARTS).map((page) => ({ path: at('docs', 'errors', `${page.area}.md`), body: page.body })),
];

const drifted = [];
for (const target of targets) {
  const name = relative(ROOT, target.path);
  // A target not generated yet is absent; any other read failure ends the
  // generation rather than being overwritten blind.
  let existing = null;
  try {
    existing = readFileSync(target.path, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') refuse('wisent_errors.lint.input', error.code === 'EISDIR' ? 'input-is-directory' : 'input-not-permitted', { what: 'the generated file', path: name, state: stateOf(target.path), error: error.message });
  }
  if (existing === target.body) {
    console.log(`unchanged  ${name}`);
    continue;
  }
  if (CHECK) {
    drifted.push(name);
    console.log(`DRIFTED    ${name}`);
    continue;
  }
  try {
    mkdirSync(dirname(target.path), { recursive: true });
    writeFileSync(target.path, target.body);
  } catch (error) {
    refuse(GENERATE, 'generated-unwritable', { target: name, state: stateOf(target.path), error: error.message });
  }
  console.log(`written    ${name}`);
}

// A part taken out of catalogue/failures/ leaves its generated module behind,
// and Swift compiles every file of its target: a generated module or page no
// target names any more is drift, and generating removes it.
const named = new Set(targets.map((target) => target.path));
const generatedIn = (directory, pattern) =>
  (existsSync(directory) ? listDirectory(directory, 'a directory of generated modules') : [])
    .filter((entry) => entry.isFile() && pattern.test(entry.name))
    .map((entry) => join(directory, entry.name));
const stale = [
  ...generatedIn(at('rust', 'src', 'failures'), /\.rs$/),
  ...generatedIn(at('swift', 'Sources', 'WisentErrors', 'Own'), /^OwnFailures.+\.swift$/),
  ...generatedIn(at('docs', 'errors'), /\.md$/),
].filter((path) => !named.has(path));
for (const path of stale) {
  const name = relative(ROOT, path);
  if (CHECK) {
    drifted.push(name);
    console.log(`STALE      ${name}`);
    continue;
  }
  try {
    unlinkSync(path);
  } catch (error) {
    const directory = relative(ROOT, dirname(path));
    refuse(GENERATE, 'generated-unremovable', { target: name, state: stateOf(path), directory, directory_state: stateOf(dirname(path)), error: error.message });
  }
  console.log(`removed    ${name}`);
}

if (CHECK && drifted.length > 0) refuse(GENERATE, 'generated-drifted', { count: String(drifted.length), drifted: drifted.join(', ') });
