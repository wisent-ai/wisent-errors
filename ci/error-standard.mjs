#!/usr/bin/env node
// The error standard a consuming repository holds itself to.
//
//   node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json]
//   node ci/error-standard.mjs catalogue <operations.json> [--json]
//
// `scan` refuses an error message that says a failure happened without saying
// which -- "did not succeed", "something went wrong" -- found inside a string
// literal of the product's source (the sentences are the catalogue's
// `generic_sentences`). Tests and build output are not read. A baseline,
// `{"<path>": {"<sentence>": <count>}}`, lets a product adopt the rule before
// every old message is rewritten: a file may hold at most its baseline count of
// each sentence, a new one is refused, and a baseline higher than what the file
// holds is refused too, so the baseline only ever shrinks.
//
// `catalogue` reads the operations a product declares (its `errors list --json`)
// and refuses an operation whose causes are malformed or lack the test or the
// documentation line each cause must have. The Rust crate's
// `Operation::problems` applies the same rules to the declarations themselves.
//
// Exits 0 when nothing is refused, 1 when something is, 2 on a usage error.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, relative } from 'node:path';
import { CODES, FAILURE_POINT_PATTERN, GENERIC_SENTENCES, RETRY_EXIT, USAGE_EXIT, genericSentencesIn, retryable } from '../js/index.mjs';

const USAGE =
  'usage: node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json]\n' +
  '       node ci/error-standard.mjs catalogue <operations.json> [--json]';

const SOURCE = new Map([
  ['.rs', false],
  ['.swift', false],
  ['.go', false],
  ['.ts', true],
  ['.tsx', true],
  ['.js', true],
  ['.mjs', true],
  ['.cjs', true],
  ['.py', true],
]);
const SKIPPED_DIRECTORIES = new Set([
  '.git', '.build', '.venv', 'node_modules', 'target', 'dist', 'build', 'Pods', 'DerivedData',
  'vendor', 'tests', 'test', '__tests__', 'Tests', 'fixtures',
]);
const TEST_FILE = /(\.test\.|\.spec\.|_test\.|Tests?\.swift$)/;

function usage(message) {
  console.error(`${message}\n${USAGE}`);
  process.exit(2);
}

function* sourceFiles(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRECTORIES.has(entry.name)) yield* sourceFiles(path);
    } else if (entry.isFile() && SOURCE.has(extname(entry.name)) && !TEST_FILE.test(entry.name)) {
      yield path;
    }
  }
}

function scan(directories, baselinePath, asJson) {
  const findings = [];
  let files = 0;
  for (const directory of directories) {
    try {
      if (!statSync(directory).isDirectory()) usage(`${directory} is not a directory`);
    } catch (error) {
      usage(`${directory} cannot be read: ${error.message}`);
    }
    for (const path of sourceFiles(directory)) {
      files += 1;
      const singleQuoted = SOURCE.get(extname(path));
      readFileSync(path, 'utf8')
        .split('\n')
        .forEach((line, index) => {
          for (const sentence of genericSentencesIn(line, singleQuoted)) {
            findings.push({ path: relative(process.cwd(), path), line: index + 1, sentence: sentence.text, reason: sentence.reason, text: line.trim() });
          }
        });
    }
  }
  let baseline = {};
  if (baselinePath) {
    try {
      baseline = JSON.parse(readFileSync(baselinePath, 'utf8'));
    } catch (error) {
      usage(`the baseline ${baselinePath} cannot be read as JSON: ${error.message}`);
    }
  }
  const counts = {};
  for (const finding of findings) {
    counts[finding.path] ??= {};
    counts[finding.path][finding.sentence] = (counts[finding.path][finding.sentence] ?? 0) + 1;
  }
  const refused = [];
  for (const finding of findings) {
    const allowed = baseline[finding.path]?.[finding.sentence] ?? 0;
    if (counts[finding.path][finding.sentence] > allowed) refused.push({ ...finding, allowed });
  }
  const stale = [];
  for (const [path, sentences] of Object.entries(baseline)) {
    for (const [sentence, allowed] of Object.entries(sentences)) {
      const held = counts[path]?.[sentence] ?? 0;
      if (held < allowed) stale.push({ path, sentence, allowed, held });
    }
  }
  if (asJson) {
    console.log(JSON.stringify({ files, findings, refused, stale }, null, 2));
  } else {
    for (const finding of refused) {
      console.log(
        `${finding.path}:${finding.line}: "${finding.sentence}" ${finding.reason} (${counts[finding.path][finding.sentence]} in this file, baseline ${finding.allowed}); declare the cause and say what failed, the state observed and what fixes it\n    ${finding.text}`,
      );
    }
    for (const entry of stale) {
      console.log(`${baselinePath}: ${entry.path} holds ${entry.held} "${entry.sentence}", the baseline allows ${entry.allowed}; lower the baseline to ${entry.held}`);
    }
    console.log(`${files} source file(s), ${findings.length} generic sentence(s), ${refused.length} refused, ${stale.length} stale baseline entr${stale.length === 1 ? 'y' : 'ies'}`);
  }
  return refused.length === 0 && stale.length === 0;
}

const CAUSE_ID = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const TEST_PATH = /^tests\/[^/]+\/[^:]+::[a-z0-9_]+$/;
const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);

function causeProblems(operation, cause) {
  const problems = [];
  const id = cause.id;
  if (typeof id !== 'string' || !CAUSE_ID.test(id)) problems.push(`cause ${JSON.stringify(id)}: the id is not lowercase words joined by '-'`);
  for (const field of ['failed', 'cause', 'observed', 'remedy']) {
    const text = cause[field];
    if (typeof text !== 'string' || !text.trim()) {
      problems.push(`cause ${id}: \`${field}\` is empty`);
      continue;
    }
    for (const sentence of GENERIC_SENTENCES) {
      if (text.toLowerCase().includes(sentence.text)) problems.push(`cause ${id}: \`${field}\` says "${sentence.text}", which ${sentence.reason}`);
    }
  }
  if (!CODES.includes(cause.code)) problems.push(`cause ${id}: code ${JSON.stringify(cause.code)} is not in the catalogue`);
  else if (cause.code === 'unknown') problems.push(`cause ${id}: a declared cause is never \`unknown\`; \`unknown\` is the catch-all a declaration replaces`);
  else if (cause.usage === true && retryable(cause.code)) problems.push(`cause ${id}: a usage refusal cannot be \`${cause.code}\`, which is retryable`);
  if (cause.usage === true && cause.exit !== USAGE_EXIT) problems.push(`cause ${id}: a usage refusal exits ${USAGE_EXIT}, not ${cause.exit}`);
  else if (CODES.includes(cause.code) && retryable(cause.code) && cause.exit !== RETRY_EXIT) problems.push(`cause ${id}: a retryable code exits ${RETRY_EXIT}, not ${cause.exit}`);
  else if (!Number.isInteger(cause.exit) || cause.exit === 0) problems.push(`cause ${id}: exit ${JSON.stringify(cause.exit)} is not a failure status`);
  if (typeof cause.test !== 'string' || !TEST_PATH.test(cause.test)) problems.push(`cause ${id}: test ${JSON.stringify(cause.test)} is not tests/<area>/<file>::<test name>`);
  if (typeof cause.doc !== 'string' || !cause.doc.startsWith(`${operation.docs}#`)) problems.push(`cause ${id}: doc ${JSON.stringify(cause.doc)} is not an anchor on the operation's page ${operation.docs}`);
  return problems;
}

function catalogue(path, asJson) {
  let operations;
  try {
    operations = JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    usage(`the catalogue ${path} cannot be read as JSON: ${error.message}`);
  }
  if (!Array.isArray(operations)) operations = operations.operations;
  if (!Array.isArray(operations)) usage(`the catalogue ${path} holds no list of operations`);
  const report = operations.map((operation) => {
    const problems = [];
    const id = operation.operation;
    if (typeof id !== 'string' || !FAILURE_POINT.test(id)) problems.push(`the id ${JSON.stringify(id)} is not a dotted lowercase path`);
    if (typeof operation.docs !== 'string' || !operation.docs.startsWith('https://')) problems.push(`docs ${JSON.stringify(operation.docs)} is not an https page`);
    const causes = Array.isArray(operation.causes) ? operation.causes : [];
    if (causes.length === 0) problems.push('declares no cause');
    causes.forEach((cause, index) => {
      if (causes.slice(0, index).some((earlier) => earlier.id === cause.id)) problems.push(`cause ${cause.id} is declared twice`);
      problems.push(...causeProblems(operation, cause));
    });
    return { operation: id, causes: causes.length, problems };
  });
  const failing = report.filter((entry) => entry.problems.length > 0);
  if (asJson) {
    console.log(JSON.stringify({ operations: report }, null, 2));
  } else {
    for (const entry of report) {
      console.log(`${entry.problems.length === 0 ? 'ok  ' : 'FAIL'}  ${entry.operation}: ${entry.causes} declared cause(s)`);
      for (const problem of entry.problems) console.log(`        ${problem}`);
    }
    console.log(`${report.length} operation(s), ${report.length - failing.length} with a complete catalogue, ${failing.length} refused`);
  }
  return failing.length === 0;
}

const [command, ...rest] = process.argv.slice(2);
const asJson = rest.includes('--json');
const words = rest.filter((word) => word !== '--json');
let passed;
if (command === 'scan') {
  const at = words.indexOf('--baseline');
  const baselinePath = at >= 0 ? words[at + 1] : null;
  if (at >= 0 && !baselinePath) usage('--baseline needs a file');
  const directories = words.filter((word, index) => index !== at && index !== at + 1 || at < 0);
  if (directories.length === 0) usage('scan needs at least one directory');
  passed = scan(directories, baselinePath, asJson);
} else if (command === 'catalogue') {
  if (words.length !== 1) usage('catalogue needs exactly one operations file');
  passed = catalogue(words[0], asJson);
} else {
  usage(command ? `unknown command ${JSON.stringify(command)}` : 'no command');
}
process.exit(passed ? 0 : 1);
