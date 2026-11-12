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
// Exits 0 when nothing is refused; every refusal is a declared cause of
// catalogue/failures/ and exits with the status it declares.

import { FAILURE_POINT_PATTERN, SENTENCES, fill, warningAnchor, warningProblems } from '../js/index.mjs';
import { Words } from './arguments.mjs';
import { describe, openDirectory, readJsonInput } from './input.mjs';
import { exitOf, guarded, refusalText } from './refuse.mjs';
import { absentTest } from './tests-held.mjs';

const USAGE = 'node ci/warning-standard.mjs <warnings.json> [--repository <dir>] [--confirmations <file>] [--json]';
const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);
const WARNINGS = 'wisent_errors.lint.warnings';

function check(path, repository, confirmationsPath, asJson) {
  let operations = readJsonInput(path, 'the warnings catalogue', 'a list of functionalities, or an object with functionalities', (value) =>
    Array.isArray(value) || Array.isArray(value?.functionalities) || Array.isArray(value?.operations) ? null : describe(value),
  );
  if (!Array.isArray(operations)) operations = operations.functionalities ?? operations.operations;
  if (repository !== null) openDirectory(repository, 'the repository');
  const confirmations = confirmationsPath === null
    ? null
    : readJsonInput(confirmationsPath, 'the confirmations', 'a list of the entries that ask for a confirmation', (value) =>
        Array.isArray(value) && value.every((entry) => typeof entry === 'string') ? null : describe(value),
      );
  const report = operations.map((operation) => {
    const problems = [];
    const id = operation.operation;
    if (typeof id !== 'string' || !FAILURE_POINT.test(id)) problems.push(fill(SENTENCES['operation-id-malformed'], { quoted_id: JSON.stringify(id), pattern: FAILURE_POINT_PATTERN }));
    const entries = Array.isArray(operation.entries) ? operation.entries : [];
    const warnings = Array.isArray(operation.warnings) ? operation.warnings : [];
    if (!Array.isArray(operation.warnings)) problems.push(fill(SENTENCES['warnings-not-list'], { operation: id, found: describe(operation.warnings) }));
    warnings.forEach((warning, index) => {
      if (warnings.slice(0, index).some((earlier) => earlier.id === warning.id)) problems.push(fill(SENTENCES['declared-twice'], { operation: id, kind: 'warning', id: warning.id }));
      problems.push(...warningProblems(warning));
      if (typeof warning.doc !== 'string' || !warning.doc.startsWith('https://') || !warning.doc.includes('#')) {
        const page = typeof warning.doc === 'string' && warning.doc.startsWith('https://') ? warning.doc.split('#')[0] : "the product's https warnings page";
        problems.push(fill(SENTENCES['warning-doc-not-anchor'], { operation: id, id: warning.id, quoted_doc: JSON.stringify(warning.doc), page, anchor: warningAnchor({ id: String(id) }, warning) }));
      }
      if (repository !== null) {
        const why = absentTest(repository, warning.test);
        if (why !== null) {
          problems.push(fill(SENTENCES['warning-test-absent'], { operation: id, id: warning.id, test: warning.test, repository, why }));
        }
      }
    });
    if (confirmations !== null && warnings.length > 0 && !entries.some((entry) => confirmations.includes(entry))) {
      problems.push(fill(SENTENCES['warning-unconfirmed'], {
        operation: id,
        count: String(warnings.length),
        warnings: warnings.map((warning) => warning.id).join(', '),
        entries: entries.join(', ') || 'none',
        confirmations: confirmationsPath,
        listed: confirmations.length ? confirmations.join(', ') : 'no entry',
      }));
    }
    return { operation: id, entries, warnings: warnings.length, problems };
  });
  const unwarned = [];
  for (const entry of confirmations ?? []) {
    if (!report.some((operation) => operation.warnings > 0 && operation.entries.includes(entry))) {
      const starts = report.filter((operation) => operation.entries.includes(entry)).map((operation) => operation.operation);
      unwarned.push(refusalText(WARNINGS, 'confirmation-unwarned', { confirmations: confirmationsPath, quoted_entry: JSON.stringify(entry), starts: starts.join(', ') || 'none' }));
    }
  }
  const failing = report.filter((operation) => operation.problems.length > 0);
  if (asJson) {
    console.log(JSON.stringify({ operations: report, unwarned }, null, 2));
  } else {
    for (const operation of report) {
      if (operation.warnings === 0 && operation.problems.length === 0) continue;
      console.log(`${operation.problems.length === 0 ? 'ok  ' : 'FAIL'}  ${operation.operation}: ${operation.warnings} declared warning(s)`);
      if (operation.problems.length > 0) {
        console.log(`        ${refusalText(WARNINGS, 'warning-refused', { operation: operation.operation, count: String(operation.problems.length), problems: `${operation.problems.length} line(s) below` }).split('\n').join('\n        ')}`);
      }
      for (const problem of operation.problems) console.log(`        ${problem}`);
    }
    for (const sentence of unwarned) console.log(`FAIL  ${sentence}`);
    const warning = report.filter((operation) => operation.warnings > 0).length;
    console.log(
      `${report.length} functionalit${report.length === 1 ? 'y' : 'ies'}, ${warning} declaring warnings, ${failing.length} refused; ${unwarned.length} confirmation${unwarned.length === 1 ? '' : 's'} with no declared warning`,
    );
  }
  if (failing.length > 0) return exitOf(WARNINGS, 'warning-refused');
  return unwarned.length > 0 ? exitOf(WARNINGS, 'confirmation-unwarned') : 0;
}

const words = new Words('ci/warning-standard.mjs', USAGE, process.argv.slice(2));
process.exitCode = guarded(() => {
  const asJson = words.flag('--json');
  const repository = words.option('--repository');
  const confirmationsPath = words.option('--confirmations');
  const [path] = words.operands('exactly one warnings catalogue', (count) => count === 1);
  return check(path, repository, confirmationsPath, asJson);
});
