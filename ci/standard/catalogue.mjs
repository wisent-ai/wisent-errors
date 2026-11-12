// `catalogue`: the functionalities a product declares (its `errors list
// --json`, whatever language declares them), held to the declaration rules of
// the library (causeProblems, the same in every runtime), the whole-catalogue
// rules, the listing's own exit and page rules, and with `--repository` the
// repository itself: each cause's test written or listed as untested with
// its reason, and each placeholder passed by some raising site.

import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { CODES, FAILURE_POINT_PATTERN, RETRY_EXIT, SENTENCES, USAGE_EXIT, anchor, causeProblems, fill, placeholders, refusal, retryable } from '../../js/index.mjs';
import { absentTest } from '../tests-held.mjs';
import { describe, openDirectory, readJsonInput } from '../input.mjs';
import { ownOperations, refusalText, refuse } from '../refuse.mjs';
import { passedNames } from './raising.mjs';

const CATALOGUE = 'wisent_errors.lint.catalogue';
const FIELDS = ['failed', 'cause', 'observed', 'remedy'];

/** The declared cause `id` of the catalogue check, as one problem line. */
function line(id, values) {
  const operation = ownOperations().find((candidate) => candidate.id === CATALOGUE);
  return refusal(operation.causes.find((cause) => cause.id === id), values);
}

/** What a listed cause says about its own exit and page, which only a listing shows. */
function listingProblems(operation, cause) {
  const problems = [];
  const named = { operation: operation.id, id: cause.id, exit: JSON.stringify(cause.exit) };
  if (cause.usage === true && cause.exit !== USAGE_EXIT) problems.push(fill(SENTENCES['listing-usage-exit'], { ...named, usage_exit: String(USAGE_EXIT) }));
  else if (CODES.includes(cause.code) && retryable(cause.code) && cause.exit !== RETRY_EXIT) problems.push(fill(SENTENCES['listing-retry-exit'], { ...named, code: cause.code, retry_exit: String(RETRY_EXIT) }));
  else if (!Number.isInteger(cause.exit) || cause.exit === 0) problems.push(fill(SENTENCES['listing-exit-not-failure'], named));
  if (typeof cause.doc !== 'string' || !cause.doc.startsWith(`${operation.docs}#`)) {
    problems.push(fill(SENTENCES['listing-doc-off-page'], { ...named, quoted_doc: JSON.stringify(cause.doc), docs: String(operation.docs), anchor: anchor(operation, cause) }));
  }
  return problems;
}

/**
 * The untested causes a repository lists, `{ path, tests: Map<test, reason> }`:
 * tests/untested-causes.json, each entry a test path a cause names and why no
 * local state can provoke it. A repository whose every cause is tested keeps
 * no such file.
 */
function untestedListing(repository) {
  const path = join(repository, 'tests', 'untested-causes.json');
  const tests = new Map();
  if (!existsSync(path)) return { path, tests };
  const listed = readJsonInput(path, 'the untested causes', 'a list of {"test": "tests/<area>/<file>::<name>", "reason": "..."}', (value) => (Array.isArray(value) ? null : describe(value)));
  listed.forEach((entry, index) => {
    if (typeof entry?.test !== 'string' || typeof entry?.reason !== 'string' || !entry.reason.trim()) {
      refuse(CATALOGUE, 'untested-listing-malformed', { untested: path, position: String(index + 1), found: describe(entry), count: String(listed.length), example: '{"test": "tests/<area>/<file>::<name>", "reason": "why no local state provokes it"}' });
    }
    tests.set(entry.test, entry.reason);
  });
  return { path, tests };
}

export function checkCatalogue(path, repository, entriesPath, sources = null) {
  const read = readJsonInput(path, 'the catalogue', 'a list of functionalities, or an object with operations', (value) =>
    Array.isArray(value) || Array.isArray(value?.operations) ? null : describe(value),
  );
  return checkListing(Array.isArray(read) ? read : read.operations, repository, entriesPath, sources);
}

/** The same, for a listing already in hand. */
export function checkListing(operations, repository, entriesPath, sources = null) {
  if (repository !== null) openDirectory(repository, 'the repository');
  const untested = repository === null ? null : untestedListing(repository);
  const passed = repository === null ? null : passedNames(repository, sources);
  const ids = operations.map((operation) => operation.operation);
  const report = operations.map((operation, position) => {
    const problems = [];
    const id = operation.operation;
    if (ids.slice(0, position).includes(id)) problems.push(fill(SENTENCES['operation-twice'], { operation: id }));
    const entries = Array.isArray(operation.entries) ? operation.entries : [];
    if (!Array.isArray(operation.entries)) problems.push(fill(SENTENCES['entries-not-list'], { operation: id, found: describe(operation.entries) }));
    const uses = Array.isArray(operation.uses) ? operation.uses : [];
    if (!Array.isArray(operation.uses)) problems.push(fill(SENTENCES['uses-not-list'], { operation: id, found: describe(operation.uses) }));
    const declared = { id, entries, uses: uses.map((used) => ({ id: used })), summary: operation.summary, docs: operation.docs, causes: [] };
    const causes = Array.isArray(operation.causes) ? operation.causes : [];
    for (const used of uses) if (used !== id && !ids.includes(used)) problems.push(fill(SENTENCES['uses-unlisted'], { operation: id, used }));
    const usedByAnother = operations.some((other) => Array.isArray(other.uses) && other.uses.includes(id));
    if (entries.length === 0 && !usedByAnother) problems.push(fill(SENTENCES['nothing-starts'], { operation: id }));
    causes.forEach((cause, index) => {
      if (causes.slice(0, index).some((earlier) => earlier.id === cause.id)) problems.push(fill(SENTENCES['declared-twice'], { operation: id, kind: 'cause', id: cause.id }));
      problems.push(...causeProblems({ ...cause, exit: null }), ...listingProblems(declared, cause));
      if (repository !== null) {
        const why = absentTest(repository, cause.test);
        if (why !== null && !untested.tests.has(cause.test)) {
          problems.push(line('test-absent', { operation: id, cause_id: cause.id, why, untested: untested.path, test: cause.test }));
        }
        for (const field of FIELDS) {
          for (const name of placeholders(String(cause[field] ?? ''))) {
            if (passed.names.has(name)) continue;
            problems.push(line('placeholder-unpassed', { operation: id, cause_id: cause.id, field, placeholder: `{${name}}`, name, repository, sites: String(passed.files), passed: [...passed.names].sort().slice(0, 40).join(', ') || 'none' }));
          }
        }
      }
    });
    return { operation: id, entries, causes: causes.length, problems: [...operationShape(declared, causes), ...problems] };
  });
  const unstarted = [];
  if (entriesPath !== null) {
    const inventory = readJsonInput(entriesPath, 'the entries', 'a list of strings, one per command, route, screen and routine', (value) =>
      Array.isArray(value) && value.every((entry) => typeof entry === 'string') ? null : describe(value),
    );
    for (const entry of inventory) {
      if (!report.some((operation) => operation.entries.includes(entry))) {
        unstarted.push(refusalText(CATALOGUE, 'entry-unstarted', { entries: entriesPath, quoted_entry: JSON.stringify(entry), count: String(inventory.length), functionalities: String(report.length) }));
      }
    }
    for (const operation of report) {
      for (const entry of operation.entries) {
        if (!inventory.includes(entry)) operation.problems.push(fill(SENTENCES['entry-uninventoried'], { operation: operation.operation, quoted_entry: JSON.stringify(entry), count: String(inventory.length), entries: entriesPath }));
      }
    }
  }
  return { report, unstarted };
}

/** The operation-level rules a listing can be held to, in the library's sentences. */
function operationShape(declared, causes) {
  const problems = [];
  const named = { operation: declared.id };
  if (typeof declared.id !== 'string' || !new RegExp(FAILURE_POINT_PATTERN).test(declared.id)) {
    problems.push(fill(SENTENCES['operation-id-malformed'], { quoted_id: JSON.stringify(declared.id), pattern: FAILURE_POINT_PATTERN }));
  }
  declared.entries.forEach((entry, index) => {
    if (typeof entry !== 'string' || !entry.trim()) problems.push(fill(SENTENCES['entry-empty'], { ...named, position: String(index + 1), count: String(declared.entries.length) }));
  });
  if (declared.uses.some((used) => used.id === declared.id)) problems.push(fill(SENTENCES['uses-itself'], named));
  if (typeof declared.summary !== 'string' || !declared.summary.trim()) problems.push(fill(SENTENCES['summary-empty'], named));
  if (typeof declared.docs !== 'string' || !declared.docs.startsWith('https://')) problems.push(fill(SENTENCES['docs-not-https'], { ...named, quoted_docs: JSON.stringify(declared.docs) }));
  if (causes.length === 0 && declared.uses.length === 0) problems.push(fill(SENTENCES['no-cause'], named));
  return problems;
}
