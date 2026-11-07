#!/usr/bin/env node
// The error standard a consuming repository holds itself to.
//
//   node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json]
//   node ci/error-standard.mjs catalogue <catalogue.json> [--repository <dir>] [--entries <entries.json>] [--json]
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
// `catalogue` reads the functionalities a product declares (its `errors list
// --json`, whatever language declares them) and refuses one whose causes are
// malformed or lack the test or the documentation line each cause must have,
// one that uses a functionality the catalogue does not list, and one nothing
// starts. The Rust crate's `Operation::problems` and `catalogue_problems` apply
// the same rules to the declarations themselves. `--repository` reads each
// cause's test from the product's checkout; `--entries` reads every entry the
// product has (a JSON list: each command, route, screen and routine) and
// refuses one no functionality names.
//
// Exits 0 when nothing is refused, 1 when something is, 2 on a usage error.

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, relative } from 'node:path';
import { CODES, FAILURE_POINT_PATTERN, GENERIC_SENTENCES, RETRY_EXIT, USAGE_EXIT, genericSentencesIn, retryable } from '../js/index.mjs';

const USAGE =
  'usage: node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json]\n' +
  '       node ci/error-standard.mjs catalogue <catalogue.json> [--repository <dir>] [--entries <entries.json>] [--json]';

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

// Why `cause`'s test is not one `repository` holds, or null when the file it
// names exists and names the test. A file is read as text, so a test of any
// language counts by its name standing as a word in it.
function absentTest(repository, cause) {
  const [file, name] = String(cause.test).split('::');
  if (!file || !name) return `${cause.test} names no file::test`;
  const path = join(repository, file);
  if (!existsSync(path)) return `${path} is absent`;
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (error) {
    return `${path} cannot be read: ${error.message}`;
  }
  return new RegExp(`\\b${name}\\b`).test(text) ? null : `${path} never names ${name}`;
}

function readJson(path, what) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    return usage(`the ${what} ${path} cannot be read as JSON: ${error.message}`);
  }
}

function catalogue(path, repository, entriesPath, asJson) {
  let operations = readJson(path, 'catalogue');
  if (!Array.isArray(operations)) operations = operations?.operations;
  if (!Array.isArray(operations)) usage(`the catalogue ${path} holds no list of functionalities`);
  if (repository !== null) {
    let directory = false;
    try {
      directory = statSync(repository).isDirectory();
    } catch (error) {
      usage(`the repository ${repository} cannot be read: ${error.message}`);
    }
    if (!directory) usage(`the repository ${repository} is not a directory, so no declared cause's test can be read from it`);
  }
  const ids = operations.map((operation) => operation.operation);
  const report = operations.map((operation, position) => {
    const problems = [];
    const id = operation.operation;
    if (typeof id !== 'string' || !FAILURE_POINT.test(id)) problems.push(`the id ${JSON.stringify(id)} is not a dotted lowercase path`);
    if (ids.slice(0, position).includes(id)) problems.push(`${id} is declared twice`);
    if (typeof operation.docs !== 'string' || !operation.docs.startsWith('https://')) problems.push(`docs ${JSON.stringify(operation.docs)} is not an https page`);
    const entries = Array.isArray(operation.entries) ? operation.entries : [];
    if (!Array.isArray(operation.entries)) problems.push('`entries` is not a list');
    if (entries.some((entry) => typeof entry !== 'string' || !entry.trim())) problems.push('an entry is empty');
    const uses = Array.isArray(operation.uses) ? operation.uses : [];
    if (!Array.isArray(operation.uses)) problems.push('`uses` is not a list');
    for (const used of uses) {
      if (used === id) problems.push('it lists itself in `uses`');
      else if (!ids.includes(used)) problems.push(`it uses ${used}, which the catalogue does not list; list every functionality the product runs`);
    }
    const usedByAnother = operations.some((other) => Array.isArray(other.uses) && other.uses.includes(id));
    if (entries.length === 0 && !usedByAnother) problems.push('nothing starts it: it names no entry and no functionality of the catalogue uses it');
    const causes = Array.isArray(operation.causes) ? operation.causes : [];
    if (causes.length === 0 && uses.length === 0) problems.push('declares no cause and uses no functionality that declares one');
    causes.forEach((cause, index) => {
      if (causes.slice(0, index).some((earlier) => earlier.id === cause.id)) problems.push(`cause ${cause.id} is declared twice`);
      problems.push(...causeProblems(operation, cause));
      if (repository !== null) {
        const why = absentTest(repository, cause);
        if (why !== null) {
          problems.push(`${id}.${cause.id} names the test ${cause.test}, which the repository does not hold: ${why}; write that test, or name the one that provokes this cause`);
        }
      }
    });
    return { operation: id, entries, causes: causes.length, problems };
  });
  const unstarted = [];
  if (entriesPath !== null) {
    const inventory = readJson(entriesPath, 'entries');
    if (!Array.isArray(inventory) || inventory.some((entry) => typeof entry !== 'string')) {
      usage(`the entries ${entriesPath} are not a JSON list of strings`);
    }
    for (const entry of inventory) {
      if (!report.some((operation) => operation.entries.includes(entry))) {
        unstarted.push(`entry ${JSON.stringify(entry)} starts no declared functionality; declare every functionality it runs and name it in their entries`);
      }
    }
    for (const operation of report) {
      for (const entry of operation.entries) {
        if (!inventory.includes(entry)) {
          operation.problems.push(`it names the entry ${JSON.stringify(entry)}, which ${entriesPath} does not hold`);
        }
      }
    }
  }
  const failing = report.filter((entry) => entry.problems.length > 0);
  if (asJson) {
    console.log(JSON.stringify({ operations: report, unstarted }, null, 2));
  } else {
    for (const entry of report) {
      console.log(`${entry.problems.length === 0 ? 'ok  ' : 'FAIL'}  ${entry.operation}: ${entry.causes} declared cause(s)`);
      for (const problem of entry.problems) console.log(`        ${problem}`);
    }
    for (const sentence of unstarted) console.log(`FAIL  ${sentence}`);
    console.log(
      `${report.length} functionalit${report.length === 1 ? 'y' : 'ies'}, ${report.length - failing.length} with a complete catalogue, ${failing.length} refused; ${unstarted.length} entr${unstarted.length === 1 ? 'y' : 'ies'} starting no declared functionality`,
    );
  }
  return failing.length === 0 && unstarted.length === 0;
}

// The value after `flag` in `words`, removing both, or null when absent.
function option(words, flag) {
  const at = words.indexOf(flag);
  if (at < 0) return null;
  const value = words[at + 1];
  if (!value || value.startsWith('--')) usage(`${flag} needs a value`);
  words.splice(at, 2);
  return value;
}

const [command, ...rest] = process.argv.slice(2);
const asJson = rest.includes('--json');
const words = rest.filter((word) => word !== '--json');
let passed;
if (command === 'scan') {
  const baselinePath = option(words, '--baseline');
  if (words.length === 0) usage('scan needs at least one directory');
  passed = scan(words, baselinePath, asJson);
} else if (command === 'catalogue') {
  const repository = option(words, '--repository');
  const entriesPath = option(words, '--entries');
  if (words.length !== 1) usage('catalogue needs exactly one catalogue file');
  passed = catalogue(words[0], repository, entriesPath, asJson);
} else {
  usage(command ? `unknown command ${JSON.stringify(command)}` : 'no command');
}
process.exit(passed ? 0 : 1);
