// A functionality's failure catalogue, for JavaScript products: the same
// declaration the Rust crate's `operation` module holds, with the same rules
// and the same JSON, so a product in either language prints one shape and is
// held to one standard.
//
// An operation is one functionality, named by its failure point: `entries`
// are every way a user or a program starts it (a command, a route, a screen,
// a routine), `uses` the functionalities it runs, whose causes it meets
// without declaring them again, and `causes` the causes of its own steps. A
// cause states which step failed, why, the state the refusal shows, what
// fixes it, its code, and the real test that provokes it.

import { CODES, FAILURE_POINT_PATTERN, GENERIC_SENTENCES, RETRY_EXIT, USAGE_EXIT, retryable } from './codes.mjs';

const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);
const CAUSE_ID = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const TEST_PATH = /^tests\/[^/]+\/[^:]+::[a-z0-9_]+$/;

/**
 * `template` with each `{name}` replaced by `values[name]`. A placeholder with
 * no value stays as written, so a value the raising code forgot is visible in
 * the sentence instead of silently becoming nothing.
 */
export function fill(template, values = {}) {
  return template.replace(/\{([^{}]*)\}/g, (whole, name) =>
    Object.prototype.hasOwnProperty.call(values, name) ? String(values[name]) : whole,
  );
}

/** What failed, why, and the state observed, as one sentence. */
export function sentence(cause, values = {}) {
  return `${fill(cause.failed, values)}: ${fill(cause.cause, values)}; observed: ${fill(cause.observed, values)}`;
}

/** What would fix it, with the values filled in. */
export function fix(cause, values = {}) {
  return fill(cause.remedy, values);
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

/** Everything wrong with one cause's declaration, each as one sentence. */
export function causeProblems(cause) {
  const problems = [];
  const id = cause.id;
  if (typeof id !== 'string' || !CAUSE_ID.test(id)) problems.push(`cause ${JSON.stringify(id)}: the id is not lowercase words joined by '-'`);
  for (const field of ['failed', 'cause', 'observed', 'remedy']) {
    const text = cause[field];
    if (typeof text !== 'string' || !text.trim()) {
      problems.push(`cause ${id}: \`${field}\` is empty`);
      continue;
    }
    for (const generic of GENERIC_SENTENCES) {
      if (text.toLowerCase().includes(generic.text)) problems.push(`cause ${id}: \`${field}\` says ${JSON.stringify(generic.text)}, which ${generic.reason}`);
    }
  }
  if (!CODES.includes(cause.code)) problems.push(`cause ${id}: code ${JSON.stringify(cause.code)} is not in the catalogue`);
  else if (cause.code === 'unknown') problems.push(`cause ${id}: a declared cause is never \`unknown\`; \`unknown\` is the catch-all a declaration replaces`);
  else if (cause.usage === true && retryable(cause.code)) problems.push(`cause ${id}: a usage refusal cannot be \`${cause.code}\`, which is retryable`);
  if (cause.exit !== undefined && cause.exit !== null) {
    if (cause.usage === true || (CODES.includes(cause.code) && retryable(cause.code))) {
      problems.push(`cause ${id}: exit ${cause.exit} is declared, but a usage refusal exits ${USAGE_EXIT} and a retryable code ${RETRY_EXIT}`);
    }
    if (!Number.isInteger(cause.exit) || cause.exit === 0 || cause.exit === USAGE_EXIT || cause.exit === RETRY_EXIT) {
      problems.push(`cause ${id}: exit ${cause.exit} is not a status of its own: 0 is success, ${USAGE_EXIT} usage and ${RETRY_EXIT} retry`);
    }
  }
  if (typeof cause.test !== 'string' || !TEST_PATH.test(cause.test)) problems.push(`cause ${id}: test ${JSON.stringify(cause.test)} is not tests/<area>/<file>::<test name>`);
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
  if (typeof id !== 'string' || !FAILURE_POINT.test(id)) problems.push(`operation ${JSON.stringify(id)}: the id is not a dotted lowercase path`);
  const entries = operation.entries ?? [];
  const uses = operation.uses ?? [];
  const causes = operation.causes ?? [];
  if (entries.some((entry) => typeof entry !== 'string' || !entry.trim())) problems.push(`operation ${id}: an entry is empty`);
  if (uses.some((used) => used.id === id)) problems.push(`operation ${id}: it lists itself in \`uses\``);
  if (typeof operation.summary !== 'string' || !operation.summary.trim()) problems.push(`operation ${id}: \`summary\` is empty`);
  if (typeof operation.docs !== 'string' || !operation.docs.startsWith('https://')) problems.push(`operation ${id}: docs ${JSON.stringify(operation.docs)} is not an https page`);
  if (causes.length === 0 && uses.length === 0) problems.push(`operation ${id}: declares no cause and uses no functionality that declares one`);
  causes.forEach((cause, index) => {
    if (causes.slice(0, index).some((earlier) => earlier.id === cause.id)) problems.push(`operation ${id}: cause ${cause.id} is declared twice`);
    for (const problem of causeProblems(cause)) problems.push(`operation ${id}: ${problem}`);
  });
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
    if (operations.slice(0, index).some((earlier) => earlier.id === operation.id)) problems.push(`operation ${operation.id} is declared twice`);
    for (const used of operation.uses ?? []) {
      if (!operations.some((listed) => listed.id === used.id)) {
        problems.push(`operation ${operation.id}: it uses ${used.id}, which the catalogue does not list; list every functionality the product runs`);
      }
    }
    const used = operations.some((other) => (other.uses ?? []).some((candidate) => candidate.id === operation.id));
    if ((operation.entries ?? []).length === 0 && !used) {
      problems.push(`operation ${operation.id}: nothing starts it: it names no entry and no functionality of the catalogue uses it`);
    }
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
