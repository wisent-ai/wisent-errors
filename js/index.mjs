// The failure envelope, for JavaScript components.
//
// Two things only: build an envelope whose derived fields cannot be wrong, and
// render it so a reader can find the source. Everything a caller decides --
// where it broke, what the layer below said, which subject it concerns -- is an
// argument. Everything derivable from the code is derived.
//
// The `cause` chain is the field this package exists for. A gateway refusing a
// request because a provider refused a token because a vault refused a read is
// three failures; reporting only the outermost is how a day goes into finding
// what the innermost already said.

import {
  CODES,
  FALLBACK,
  FAILURE_POINT_PATTERN,
  MEANINGS,
  RETRY_EXIT,
  exitCode,
  httpStatus,
  fromUpstreamStatus,
  operatorSummary,
  outage,
  retryable,
  severity,
} from './codes.mjs';

const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);
const DETAIL_LIMIT = 2000;

export class FailureError extends Error {
  constructor(envelope) {
    super(`${envelope.failure_point}: ${envelope.detail}`);
    this.name = 'FailureError';
    this.envelope = envelope;
  }
}

const trimmed = (value, field) => {
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError(`${field} must be a non-empty string`);
  }
  return value.trim();
};

/**
 * Build a failure envelope.
 *
 * `detail` is required on purpose. A failure reported without the reason the
 * layer below gave is the defect this package exists to prevent, and making it
 * optional is how that defect gets written again.
 */
export function failure({ failurePoint, code, service, impact, detail, cause, context }) {
  const point = trimmed(failurePoint, 'failurePoint');
  if (!FAILURE_POINT.test(point)) {
    throw new TypeError(`failurePoint ${JSON.stringify(point)} is not <service>.<surface>.<operation>`);
  }
  if (!CODES.includes(code)) {
    throw new TypeError(`code ${JSON.stringify(code)} is not in the catalogue; one of ${CODES.join(', ')}`);
  }
  const envelope = {
    failure_point: point,
    error_code: code,
    service: trimmed(service, 'service'),
    impact: trimmed(impact, 'impact'),
    severity: severity(code),
    retryable: retryable(code),
    outage: outage(code),
    detail: trimmed(detail, 'detail').slice(0, DETAIL_LIMIT),
  };
  if (cause !== undefined && cause !== null) {
    envelope.cause = cause instanceof FailureError ? cause.envelope : cause;
  }
  if (context !== undefined && context !== null) {
    envelope.context = { ...context };
  }
  return envelope;
}

/** The same, thrown. */
export function raise(fields) {
  throw new FailureError(failure(fields));
}

/**
 * One line for a human, and the envelope for everything else.
 *
 * The sentence answers the only question that decides what the reader does
 * next: ours or theirs. The JSON follows on the same line so grep finds both.
 */
export function render(envelope) {
  const retry = envelope.retryable ? '; retry later' : '; retrying will not help';
  const whose = envelope.outage ? 'our failure' : 'the request or its credentials';
  return [
    `${operatorSummary(envelope.error_code)} — ${whose}${retry}`,
    JSON.stringify(envelope),
  ].join(' ');
}

/** Flatten a cause chain, outermost first, for a reader in a hurry. */
export function chain(envelope) {
  const rows = [];
  for (let node = envelope; node; node = node.cause) {
    rows.push(`${node.failure_point} [${node.error_code}] ${node.detail}`);
  }
  return rows;
}

export {
  CODES,
  FALLBACK,
  MEANINGS,
  RETRY_EXIT,
  exitCode,
  fromUpstreamStatus,
  httpStatus,
  operatorSummary,
  outage,
  retryable,
  severity,
};
