// The failure envelope, for JavaScript components.
//
// Two things only: build an envelope whose derived fields cannot be wrong, and
// render it so a reader can find the source. Everything a caller decides --
// where it broke, what the layer below said, which subject it concerns -- is an
// argument. Everything derivable from the code comes from the catalogue.

import {
  CODES,
  FAILURE_POINT_PATTERN,
  FALLBACK,
  SEVERITIES,
  MEANINGS,
  RETRY_EXIT,
  codeOrNull,
  exitCode,
  fromUpstreamStatus,
  httpStatus,
  isCode,
  operatorSummary,
  outage,
  retryable,
  severity,
} from './codes.mjs';

const FAILURE_POINT = new RegExp(FAILURE_POINT_PATTERN);

/** This package's own bound. A product's bound is the product's to choose. */
export const DETAIL_LIMIT = 2000;

/**
 * Trim a detail to a bound. A hard cut, which is what the fleet emits.
 *
 * The limit is an argument because the width is a product's own decision --
 * stado and probierz keep 300, wisent-customer-support 400, wisent-tools 500 --
 * while the rule for how to cut is the thing that was written six times.
 *
 * An earlier version of this backed up to the last word edge within 24
 * characters of the bound. Nothing in the fleet did that: four products cut
 * hard, and adopting the nicer rule silently moved the bytes of an
 * operator-visible line for every detail longer than the bound that contains a
 * space, which is nearly all of them. Ends are still stripped, because
 * whitespace around a detail is never information.
 */
export function trimDetail(text, limit = DETAIL_LIMIT) {
  const value = String(text ?? '').trim();
  return value.length <= limit ? value : value.slice(0, limit);
}

/**
 * The same, cut back to a word edge when one falls within `slack` of the bound.
 *
 * Separate and opt-in, because it changes emitted bytes. Worth having where a
 * detail is read by a person rather than parsed, and worth never being a default.
 */
export function trimDetailAtWordEdge(text, limit = DETAIL_LIMIT, slack = 24) {
  const cut = trimDetail(text, limit);
  const value = String(text ?? '').trim();
  if (cut.length < limit) return cut;
  if (/\s/.test(value.charAt(limit))) return cut.trimEnd();
  // `edge > 0` matters: lastIndexOf returns -1 when there is no space at all, and
  // for any limit under `slack` that -1 passes a bare `edge > limit - slack`, which
  // silently dropped the last character. No fleet width is that small; the guard
  // was still wrong rather than benignly unreachable.
  const edge = cut.lastIndexOf(' ');
  return (edge > 0 && edge > limit - slack ? cut.slice(0, edge) : cut).trimEnd();
}

export class FailureError extends Error {
  constructor(envelope) {
    super(`${envelope.failure_point}: ${envelope.detail ?? operatorSummary(envelope.error_code)}`);
    this.name = 'FailureError';
    this.envelope = envelope;
  }
}

const required = (value, field) => {
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError(`${field} must be a non-empty string`);
  }
  return value.trim();
};

const optional = (value) => {
  const text = String(value ?? '').trim();
  return text || null;
};

/**
 * Build a failure envelope.
 *
 * `detail` and `impact` are optional and serialize as `null` when absent, rather
 * than disappearing: a stable key set is what makes these lines queryable in a
 * log store, and three products in this fleet have no impact axis at all while
 * two legitimately report a failure with nothing further to say. Making either
 * mandatory buys `impact: "unknown"` and `detail: "unknown"`, which is a worse
 * lie than an absent value. `cause` and `context` are structural and are omitted
 * when there is nothing to put in them.
 *
 * Throws on anything malformed. Inside an error path, where throwing destroys
 * the diagnosis being carried, use `failureOrFallback`.
 */
export function failure({ failurePoint, code, service, impact, detail, cause, context }) {
  const point = required(failurePoint, 'failurePoint');
  if (!FAILURE_POINT.test(point)) {
    throw new TypeError(`failurePoint ${JSON.stringify(point)} is not a dotted lowercase path`);
  }
  if (!CODES.includes(code)) {
    throw new TypeError(`code ${JSON.stringify(code)} is not in the catalogue; one of ${CODES.join(', ')}`);
  }
  const envelope = {
    failure_point: point,
    error_code: code,
    service: required(service, 'service'),
    impact: optional(impact),
    severity: severity(code),
    retryable: retryable(code),
    outage: outage(code),
    detail: detail === undefined || detail === null ? null : trimDetail(required(detail, 'detail'), DETAIL_LIMIT),
  };
  if (cause !== undefined && cause !== null) {
    envelope.cause = cause instanceof FailureError ? cause.envelope : cause;
  }
  if (context !== undefined && context !== null && Object.keys(context).length > 0) {
    envelope.context = { ...context };
  }
  return envelope;
}

/**
 * The same, but it never throws.
 *
 * Reporting a failure must not itself fail: an error path that dies takes the
 * diagnosis with it, which is how hours of an outage end up with no record of
 * why. An unknown code becomes the fallback, and anything malformed is recorded
 * in `context` under a `wisent_errors.` key, so the defect travels in the data
 * instead of becoming an exception raised inside a `catch`.
 */
export function failureOrFallback(fields = {}) {
  const notes = {};

  let point = optional(fields.failurePoint);
  if (point === null) {
    point = 'unknown';
    notes['wisent_errors.failure_point'] = 'absent';
  } else if (!FAILURE_POINT.test(point)) {
    notes['wisent_errors.failure_point'] = 'malformed';
  }

  let code = fields.code;
  if (!CODES.includes(code)) {
    notes['wisent_errors.error_code'] =
      code === undefined || code === null ? 'absent' : `off-catalogue: ${String(code)}`;
    code = FALLBACK;
  }

  const service = optional(fields.service);
  if (service === null) notes['wisent_errors.service'] = 'absent';

  const envelope = {
    failure_point: point,
    error_code: code,
    service: service ?? 'unknown',
    impact: optional(fields.impact),
    severity: severity(code),
    retryable: retryable(code),
    outage: outage(code),
    detail: optional(fields.detail) === null ? null : trimDetail(optional(fields.detail), DETAIL_LIMIT),
  };
  if (fields.cause !== undefined && fields.cause !== null) {
    envelope.cause = fields.cause instanceof FailureError ? fields.cause.envelope : fields.cause;
  }
  const context = { ...(fields.context ?? {}), ...notes };
  if (Object.keys(context).length > 0) envelope.context = context;
  return envelope;
}

/** The code when the catalogue knows it, otherwise the fallback. Never throws. */
export function codeOrFallback(text) {
  return CODES.includes(text) ? text : FALLBACK;
}

/** The same as `failure`, thrown. */
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
    rows.push(`${node.failure_point} [${node.error_code}] ${node.detail ?? '-'}`);
  }
  return rows;
}

export {
  CODES,
  FAILURE_POINT_PATTERN,
  FALLBACK,
  MEANINGS,
  RETRY_EXIT,
  SEVERITIES,
  codeOrNull,
  exitCode,
  fromUpstreamStatus,
  httpStatus,
  isCode,
  operatorSummary,
  outage,
  retryable,
  severity,
};
