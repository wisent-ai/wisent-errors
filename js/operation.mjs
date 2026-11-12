// A functionality's failure catalogue, for JavaScript products: the same
// declaration the Rust crate's `operation` module holds, with the same rules
// and the same JSON, so a product in either language prints one shape and is
// held to one standard. The rules and their sentences come from
// catalogue/declaration.json, generated into js/declaration.mjs.
//
// An operation is one functionality, named by its failure point: `entries`
// are every way a user or a program starts it (a command, a route, a screen,
// a routine), `uses` the functionalities it runs, whose causes it meets
// without declaring them again, and `causes` the causes of its own steps. A
// cause states which step failed, why, the state the refusal shows, what
// fixes it, its code, and the real test that provokes it.

import { CODES, FAILURE_POINT_PATTERN, GENERIC_SENTENCES, RETRY_EXIT, USAGE_EXIT, retryable } from './codes.mjs';
import { CAUSE_ID_PATTERN, FIELD_MEANINGS, SENTENCES, TEST_PATH_PATTERN } from './declaration.mjs';
import { fill, templateProblems } from './template.mjs';
import { warningDeclarationProblems } from './warning.mjs';

const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);
export const CAUSE_ID = new RegExp(CAUSE_ID_PATTERN);
export const TEST_PATH = new RegExp(TEST_PATH_PATTERN);
export const CAUSE_FIELDS = Object.freeze(['failed', 'cause', 'observed', 'remedy']);
const say = (key, values) => fill(SENTENCES[key], values);

/** What failed, why, and the state observed, as one sentence. */
export function sentence(cause, values = {}) {
  return `${fill(cause.failed, values)}: ${fill(cause.cause, values)}; observed: ${fill(cause.observed, values)}`;
}

/** What would fix it, with the values filled in. */
export function fix(cause, values = {}) {
  return fill(cause.remedy, values);
}

/** The sentence and the fix as one line: what a thrown refusal says. */
export function refusal(cause, values = {}) {
  return `${sentence(cause, values)}; fix: ${fix(cause, values)}`;
}

/**
 * The exit status this cause leaves a command with, given the product's own
 * failure status: the usage status for a usage refusal, the cause's own
 * declared status, the retry status for a retryable code, the product's
 * otherwise.
 */
export function causeExit(cause, failureExit) {
  if (cause.usage === true) return USAGE_EXIT;
  if (Number.isInteger(cause.exit)) return cause.exit;
  return retryable(cause.code) ? RETRY_EXIT : failureExit;
}

/** The anchor of a cause's line on its functionality's page. */
export function anchor(operation, cause) {
  return `${operation.id.replaceAll('.', '-')}-${cause.id}`;
}

/**
 * The problems of the texts every declaration kind shares: each field empty,
 * generic, or holding a placeholder the renderer never fills; `kind` is
 * `cause` or `warning`.
 */
export function textProblems(kind, id, fields) {
  const problems = [];
  for (const [field, text] of fields) {
    if (typeof text !== 'string' || !text.trim()) {
      problems.push(say('field-empty', { kind, id, field, meaning: FIELD_MEANINGS[field] }));
      continue;
    }
    for (const generic of GENERIC_SENTENCES) {
      if (text.toLowerCase().includes(generic.text)) problems.push(say('field-generic', { kind, id, field, quoted_text: JSON.stringify(generic.text), reason: generic.reason }));
    }
    problems.push(...templateProblems(kind, id, field, text));
  }
  return problems;
}

/** Everything wrong with one cause's declaration, each as one sentence. */
export function causeProblems(cause) {
  const problems = [];
  const id = cause.id;
  if (typeof id !== 'string' || !CAUSE_ID.test(id)) problems.push(say('id-malformed', { kind: 'cause', quoted_id: JSON.stringify(id), pattern: CAUSE_ID_PATTERN }));
  problems.push(...textProblems('cause', id, CAUSE_FIELDS.map((field) => [field, cause[field]])));
  const codes = CODES.filter((code) => code !== 'unknown').join(', ');
  if (!CODES.includes(cause.code)) problems.push(say('code-off-catalogue', { id, quoted_code: JSON.stringify(cause.code), codes }));
  else if (cause.code === 'unknown') problems.push(say('code-unknown', { id, codes }));
  else if (cause.usage === true && retryable(cause.code)) problems.push(say('usage-retryable', { id, code: cause.code }));
  if (cause.exit !== undefined && cause.exit !== null) {
    const limits = { id, exit: String(cause.exit), usage_exit: String(USAGE_EXIT), retry_exit: String(RETRY_EXIT) };
    if (cause.usage === true || (CODES.includes(cause.code) && retryable(cause.code))) problems.push(say('exit-beside-derived', limits));
    if (!Number.isInteger(cause.exit) || cause.exit === 0 || cause.exit === USAGE_EXIT || cause.exit === RETRY_EXIT) problems.push(say('exit-not-own', limits));
  }
  if (typeof cause.test !== 'string' || !TEST_PATH.test(cause.test)) problems.push(say('test-malformed', { kind: 'cause', id, quoted_test: JSON.stringify(cause.test), pattern: TEST_PATH_PATTERN }));
  return problems;
}

/**
 * Everything wrong with one functionality's declaration: a malformed id, an
 * empty entry, a functionality that uses itself, one with no cause and
 * nothing it uses, a duplicate cause, a cause that is not one, a page that
 * is not https. What only the whole catalogue shows is `catalogueProblems`.
 */
export function operationProblems(operation) {
  const problems = [];
  const id = operation.id;
  const values = { operation: id };
  if (typeof id !== 'string' || !FAILURE_POINT.test(id)) problems.push(say('operation-id-malformed', { quoted_id: JSON.stringify(id), pattern: FAILURE_POINT_PATTERN }));
  const entries = operation.entries ?? [];
  const uses = operation.uses ?? [];
  const causes = operation.causes ?? [];
  entries.forEach((entry, index) => {
    if (typeof entry !== 'string' || !entry.trim()) problems.push(say('entry-empty', { ...values, position: String(index + 1), count: String(entries.length) }));
  });
  if (uses.some((used) => used.id === id)) problems.push(say('uses-itself', values));
  if (typeof operation.summary !== 'string' || !operation.summary.trim()) problems.push(say('summary-empty', values));
  if (typeof operation.docs !== 'string' || !operation.docs.startsWith('https://')) problems.push(say('docs-not-https', { ...values, quoted_docs: JSON.stringify(operation.docs) }));
  if (causes.length === 0 && uses.length === 0) problems.push(say('no-cause', values));
  causes.forEach((cause, index) => {
    if (causes.slice(0, index).some((earlier) => earlier.id === cause.id)) problems.push(say('declared-twice', { ...values, kind: 'cause', id: cause.id }));
    for (const problem of causeProblems(cause)) problems.push(`operation ${id}: ${problem}`);
  });
  problems.push(...warningDeclarationProblems(operation));
  return problems;
}

/**
 * What only a product's whole catalogue shows: a functionality declared
 * twice, one that uses a functionality the catalogue does not list, and one
 * nothing starts.
 */
export function catalogueProblems(operations) {
  const problems = [];
  operations.forEach((operation, index) => {
    const values = { operation: operation.id };
    if (operations.slice(0, index).some((earlier) => earlier.id === operation.id)) problems.push(say('operation-twice', values));
    for (const used of operation.uses ?? []) {
      if (!operations.some((listed) => listed.id === used.id)) problems.push(say('uses-unlisted', { ...values, used: used.id }));
    }
    const used = operations.some((other) => (other.uses ?? []).some((candidate) => candidate.id === operation.id));
    if ((operation.entries ?? []).length === 0 && !used) problems.push(say('nothing-starts', values));
  });
  return problems;
}

/**
 * Every cause a functionality can meet: its own, then those of each
 * functionality it uses, transitively, each functionality visited once, as
 * `{ owner, cause }`.
 */
export function met(operation, seen = new Set()) {
  if (seen.has(operation.id)) return [];
  seen.add(operation.id);
  const found = (operation.causes ?? []).map((cause) => ({ owner: operation.id, cause }));
  for (const used of operation.uses ?? []) found.push(...met(used, seen));
  return found;
}

/** The catalogue as the JSON document every product prints from `errors list|show --json`. */
export function catalogue(operation, failureExit) {
  return {
    operation: operation.id,
    entries: [...(operation.entries ?? [])],
    uses: (operation.uses ?? []).map((used) => used.id),
    summary: operation.summary,
    docs: operation.docs,
    causes: (operation.causes ?? []).map((cause) => ({
      id: cause.id,
      code: cause.code,
      exit: causeExit(cause, failureExit),
      retryable: retryable(cause.code),
      usage: cause.usage === true,
      failed: cause.failed,
      cause: cause.cause,
      observed: cause.observed,
      remedy: cause.remedy,
      test: cause.test,
      doc: `${operation.docs}#${anchor(operation, cause)}`,
    })),
  };
}
