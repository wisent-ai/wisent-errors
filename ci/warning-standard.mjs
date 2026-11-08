#!/usr/bin/env node
// The warning standard a consuming repository holds itself to.
//
//   node ci/warning-standard.mjs <warnings.json> [--repository <dir>] [--confirmations <file>] [--json]
//
// Reads the warnings a product declares (its `warnings list --json`, whatever
// language declares them) and refuses a warning that is malformed, names an
// unknown hazard, or lacks its test or its documentation entry.
//
// `--confirmations` names a JSON list of every entry of the product that asks
// for a confirmation before it acts (a `--yes` form, a typed phrase, a
// confirming button), as the product's own inventory reads them. A warning and
// a confirmation stand for the same thing, so each is refused without the
// other: an entry that asks for a confirmation while no functionality it
// starts declares what the confirmation is for, and a functionality that
// declares a warning while none of its entries asks for one, so the warning is
// never read before it runs. That is also what keeps warnings off ordinary
// reads and recoverable edits: what asks for no confirmation declares none.
//
// Exits 0 when nothing is refused, 1 when something is, 2 on a usage error.

import { readFileSync, statSync } from 'node:fs';
import { FAILURE_POINT_PATTERN, warningProblems } from '../js/index.mjs';
import { absentTest } from './tests-held.mjs';

const USAGE = 'usage: node ci/warning-standard.mjs <warnings.json> [--repository <dir>] [--confirmations <file>] [--json]';
const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);

function usage(message) {
  console.error(`${message}\n${USAGE}`);
  process.exit(2);
}

function readJson(path, what) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    return usage(`the ${what} ${path} cannot be read as JSON: ${error.message}`);
  }
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

function check(path, repository, confirmationsPath, asJson) {
  let operations = readJson(path, 'warnings catalogue');
  if (!Array.isArray(operations)) operations = operations?.functionalities ?? operations?.operations;
  if (!Array.isArray(operations)) usage(`the warnings catalogue ${path} holds no list of functionalities`);
  if (repository !== null) {
    let directory = false;
    try {
      directory = statSync(repository).isDirectory();
    } catch (error) {
      usage(`the repository ${repository} cannot be read: ${error.message}`);
    }
    if (!directory) usage(`the repository ${repository} is not a directory, so no declared warning's test can be read from it`);
  }
  const confirmations = confirmationsPath === null ? null : readJson(confirmationsPath, 'confirmations');
  if (confirmations !== null && (!Array.isArray(confirmations) || confirmations.some((entry) => typeof entry !== 'string'))) {
    usage(`the confirmations ${confirmationsPath} are not a JSON list of entries`);
  }
  const report = operations.map((operation) => {
    const problems = [];
    const id = operation.operation;
    if (typeof id !== 'string' || !FAILURE_POINT.test(id)) problems.push(`the id ${JSON.stringify(id)} is not a dotted lowercase path`);
    const entries = Array.isArray(operation.entries) ? operation.entries : [];
    const warnings = Array.isArray(operation.warnings) ? operation.warnings : [];
    if (!Array.isArray(operation.warnings)) problems.push('`warnings` is not a list');
    warnings.forEach((warning, index) => {
      if (warnings.slice(0, index).some((earlier) => earlier.id === warning.id)) problems.push(`warning ${warning.id} is declared twice`);
      problems.push(...warningProblems(warning));
      if (typeof warning.doc !== 'string' || !warning.doc.startsWith('https://') || !warning.doc.includes('#')) {
        problems.push(`warning ${warning.id}: doc ${JSON.stringify(warning.doc)} is not an anchor on an https warnings page`);
      }
      if (repository !== null) {
        const why = absentTest(repository, warning.test);
        if (why !== null) {
          problems.push(`${id}.${warning.id} names the test ${warning.test}, which the repository does not hold: ${why}; write that test, or name the one that shows this warning`);
        }
      }
    });
    if (confirmations !== null && warnings.length > 0 && !entries.some((entry) => confirmations.includes(entry))) {
      problems.push(
        `it declares ${warnings.length} warning(s), but none of its entries (${entries.join(', ') || 'none'}) asks for a confirmation in ${confirmationsPath}, so the warning is never read before it runs; ask for one, or drop a warning nothing needs`,
      );
    }
    return { operation: id, entries, warnings: warnings.length, problems };
  });
  const unwarned = [];
  for (const entry of confirmations ?? []) {
    if (!report.some((operation) => operation.warnings > 0 && operation.entries.includes(entry))) {
      unwarned.push(
        `entry ${JSON.stringify(entry)} asks for a confirmation, but no functionality it starts declares what the confirmation is for; declare the warning, or stop asking for a confirmation nothing needs`,
      );
    }
  }
  const failing = report.filter((operation) => operation.problems.length > 0);
  if (asJson) {
    console.log(JSON.stringify({ operations: report, unwarned }, null, 2));
  } else {
    for (const operation of report) {
      if (operation.warnings === 0 && operation.problems.length === 0) continue;
      console.log(`${operation.problems.length === 0 ? 'ok  ' : 'FAIL'}  ${operation.operation}: ${operation.warnings} declared warning(s)`);
      for (const problem of operation.problems) console.log(`        ${problem}`);
    }
    for (const sentence of unwarned) console.log(`FAIL  ${sentence}`);
    const warning = report.filter((operation) => operation.warnings > 0).length;
    console.log(
      `${report.length} functionalit${report.length === 1 ? 'y' : 'ies'}, ${warning} declaring warnings, ${failing.length} refused; ${unwarned.length} confirmation${unwarned.length === 1 ? '' : 's'} with no declared warning`,
    );
  }
  return failing.length === 0 && unwarned.length === 0;
}

const words = process.argv.slice(2);
const asJson = words.includes('--json');
const rest = words.filter((word) => word !== '--json');
const repository = option(rest, '--repository');
const confirmationsPath = option(rest, '--confirmations');
if (rest.length !== 1) usage(rest.length === 0 ? 'no warnings catalogue named' : `exactly one warnings catalogue, not ${rest.join(' ')}`);
process.exit(check(rest[0], repository, confirmationsPath, asJson) ? 0 : 1);
