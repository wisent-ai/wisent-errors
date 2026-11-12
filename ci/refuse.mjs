// How this repository's own commands refuse: every refusal is a cause
// declared in catalogue/failures/ (or by the parts loader itself), printed as
// what failed, why and the state observed, then what fixes it, then which
// declared cause it is and the page that lists it, and the command exits
// with the status the cause declares.
//
//   Error: <failed>: <cause>; observed: <observed>
//   fix: <remedy>
//   cause: <operation>.<cause id>; <page>#<anchor>

import { anchor, causeExit, fix, sentence, unfilled } from '../js/index.mjs';
import { PARTS, PartsError, operationsFor, readParts } from '../codegen/parts.mjs';

let loaded = null;

/** This repository's own commands' functionalities, the parts loader's among them. */
export function ownOperations() {
  loaded ??= operationsFor('node', readParts(), [PARTS]);
  return loaded;
}

function declared(operationId, causeId) {
  const operations = ownOperations();
  const operation = operations.find((candidate) => candidate.id === operationId);
  const cause = operation?.causes.find((candidate) => candidate.id === causeId);
  if (cause === undefined) {
    throw new PartsError('raised-undeclared', {
      raised: `${operationId}.${causeId}`,
      declared: operation === undefined ? `no operation ${operationId}; operations: ${operations.map((candidate) => candidate.id).join(', ')}` : `${operationId} declares ${operation.causes.map((candidate) => candidate.id).join(', ')}`,
    });
  }
  return { operation, cause };
}

/** The three lines a refusal prints, for a cause and the values its site knows. */
export function refusal(operation, cause, values) {
  const missing = unfilled([cause.failed, cause.cause, cause.observed, cause.remedy], values);
  const gap = missing.length ? `\nwisent_errors.unfilled: ${missing.join(', ')}` : '';
  return `Error: ${sentence(cause, values)}\nfix: ${fix(cause, values)}\ncause: ${operation.id}.${cause.id}; ${operation.docs}#${anchor(operation, cause)}${gap}`;
}

/** Print the declared refusal on stderr and exit with the status it declares. */
export function refuse(operationId, causeId, values) {
  let found;
  try {
    found = declared(operationId, causeId);
  } catch (error) {
    if (!(error instanceof PartsError)) throw error;
    found = { operation: error.operation, cause: error.declared };
    values = error.values;
  }
  console.error(refusal(found.operation, found.cause, values));
  process.exit(causeExit(found.cause, 1));
}

/** The refusal of a cause, as text, for a command that lists several before it exits. */
export function refusalText(operationId, causeId, values) {
  const { operation, cause } = guarded(() => declared(operationId, causeId));
  return refusal(operation, cause, values);
}

/** The exit status a cause declares. */
export const exitOf = (operationId, causeId) => causeExit(guarded(() => declared(operationId, causeId)).cause, 1);

/** Run `body`, turning a refusal of the parts loader into its declared refusal. */
export function guarded(body) {
  try {
    return body();
  } catch (error) {
    if (!(error instanceof PartsError)) throw error;
    console.error(refusal(error.operation, error.declared, error.values));
    return process.exit(causeExit(error.declared, 1));
  }
}
