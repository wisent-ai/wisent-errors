#!/usr/bin/env node
// The error standard a consuming repository holds itself to.
//
//   node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json]
//   node ci/error-standard.mjs catalogue <catalogue.json> [--repository <dir>] [--sources <path>,...] [--entries <entries.json>] [--json]
//   node ci/error-standard.mjs errors [--json]
//
// `scan` refuses an error message that says a failure happened without saying
// which -- "did not succeed", "something went wrong" -- found inside a string
// literal of the product's source (the catalogue's `generic_sentences`), held
// to a baseline `{"<path>": {"<sentence>": <count>}}` that only shrinks.
//
// `catalogue` reads the functionalities a product declares (its `errors list
// --json`, whatever language declares them) and holds each cause to the
// declaration rules every runtime applies (catalogue/declaration.json): no
// placeholder the renderer never fills, no cause that only wraps the raw text
// of the layer below, no raw text outside `observed`. `--repository` also
// reads the repository: each cause's test is written or listed in
// tests/untested-causes.json with why it cannot be provoked locally, and each
// placeholder is passed by some raising site of its source (the whole
// repository but its tests, or the paths `--sources` names). `--entries`
// refuses an entry no functionality names.
//
// `errors` prints this package's own failure catalogue, as any product's
// `errors list --json` prints its own.
//
// Exits 0 when nothing is refused; every refusal is a declared cause of
// catalogue/failures/ and exits with the status it declares.

import { catalogue as listing } from '../js/index.mjs';
import { Words } from './arguments.mjs';
import { exitOf, guarded, ownOperations, refusalText } from './refuse.mjs';
import { checkCatalogue } from './standard/catalogue.mjs';
import { scanSources } from './standard/scan.mjs';

const USAGE =
  'node ci/error-standard.mjs scan <dir>... [--baseline <file>] [--json] | ' +
  'catalogue <catalogue.json> [--repository <dir>] [--sources <path>,...] [--entries <entries.json>] [--json] | errors [--json]';

function scan(words, asJson) {
  const baselinePath = words.option('--baseline');
  const directories = words.operands('at least one source directory', (count) => count > 0);
  const { files, findings, refused, stale } = scanSources(directories, baselinePath);
  if (asJson) {
    console.log(JSON.stringify({ files, findings, refused, stale }, null, 2));
  } else {
    for (const finding of refused) {
      console.log(refusalText('wisent_errors.lint.scan', 'generic-sentence-held', { path: finding.path, line: String(finding.line), quoted_sentence: JSON.stringify(finding.sentence), reason: finding.reason, allowed: String(finding.allowed), held: String(finding.held), text: finding.text }));
    }
    for (const entry of stale) {
      console.log(refusalText('wisent_errors.lint.scan', 'baseline-stale', { path: entry.path, baseline: baselinePath, quoted_sentence: JSON.stringify(entry.sentence), allowed: String(entry.allowed), held: String(entry.held) }));
    }
    console.log(`${files} source file(s), ${findings.length} generic sentence(s), ${refused.length} refused, ${stale.length} stale baseline entr${stale.length === 1 ? 'y' : 'ies'}`);
  }
  if (refused.length > 0) return exitOf('wisent_errors.lint.scan', 'generic-sentence-held');
  return stale.length > 0 ? exitOf('wisent_errors.lint.scan', 'baseline-stale') : 0;
}

function catalogue(words, asJson) {
  const repository = words.option('--repository');
  const sources = words.option('--sources');
  const entriesPath = words.option('--entries');
  const [path] = words.operands('exactly one catalogue file', (count) => count === 1);
  const { report, unstarted } = checkCatalogue(path, repository, entriesPath, sources === null ? null : sources.split(','));
  const failing = report.filter((entry) => entry.problems.length > 0);
  if (asJson) {
    console.log(JSON.stringify({ operations: report, unstarted }, null, 2));
  } else {
    for (const entry of report) {
      console.log(`${entry.problems.length === 0 ? 'ok  ' : 'FAIL'}  ${entry.operation}: ${entry.causes} declared cause(s)`);
      if (entry.problems.length > 0) {
        console.log(`        ${refusalText('wisent_errors.lint.catalogue', 'declaration-refused', { operation: entry.operation, count: String(entry.problems.length), problems: `${entry.problems.length} line(s) below` }).split('\n').join('\n        ')}`);
      }
      for (const problem of entry.problems) console.log(`        ${problem}`);
    }
    for (const sentence of unstarted) console.log(`FAIL  ${sentence}`);
    console.log(
      `${report.length} functionalit${report.length === 1 ? 'y' : 'ies'}, ${report.length - failing.length} with a complete catalogue, ${failing.length} refused; ${unstarted.length} entr${unstarted.length === 1 ? 'y' : 'ies'} starting no declared functionality`,
    );
  }
  if (failing.length > 0) return exitOf('wisent_errors.lint.catalogue', 'declaration-refused');
  return unstarted.length > 0 ? exitOf('wisent_errors.lint.catalogue', 'entry-unstarted') : 0;
}

function errors(words, asJson) {
  words.operands('no operand', (count) => count === 0);
  const operations = ownOperations().map((operation) => listing(operation, 1));
  if (asJson) {
    console.log(JSON.stringify(operations, null, 2));
  } else {
    for (const operation of operations) console.log(`${operation.operation}: ${operation.causes.map((cause) => cause.id).join(', ') || 'uses ' + operation.uses.join(', ')}`);
  }
  return 0;
}

const words = new Words('ci/error-standard.mjs', USAGE, process.argv.slice(2), ['scan', 'catalogue', 'errors']);
process.exitCode = guarded(() => {
  const command = words.command();
  const asJson = words.flag('--json');
  return { scan, catalogue, errors }[command](words, asJson);
});
