// How this package refuses the calls made to it: each refusal is a cause of
// its own failure catalogue (catalogue/failures/, generated into
// js/failures.mjs), thrown as a DeclaredError that names the operation, the
// cause and the values the raising site knew.

import { CODES } from './codes.mjs';
import { ENVELOPE_BUILD } from './failures.mjs';
import { refusal } from './operation.mjs';

/**
 * A refusal of a declared cause. A TypeError, as the strict builders threw
 * before their causes were declared, so a caller catching TypeError still
 * catches it.
 */
export class DeclaredError extends TypeError {
  constructor(operation, cause, values) {
    super(refusal(cause, values));
    this.name = 'DeclaredError';
    this.operation = operation.id;
    this.cause = cause.id;
    this.code = cause.code;
    this.values = { ...values };
  }
}

/** Throw the cause `causeId` of `operation` with the values its site knows. */
export function raiseDeclared(operation, causeId, values) {
  const cause = operation.causes.find((candidate) => candidate.id === causeId);
  throw new DeclaredError(operation, cause, values);
}

const LETTER = /^[a-z]$/;
const ALLOWED = /^[a-z0-9_-]$/;

/** The point a malformed one most likely meant: lowercase words joined by '-', segments by '.'. */
function suggest(point) {
  const segments = point
    .split('.')
    .map((segment) => segment.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^[^a-z]+/, '').replace(/-+$/, ''))
    .filter(Boolean);
  return `'${segments.length ? segments.join('.') : 'stado.fleet.enroll'}'`;
}

/**
 * Why `point` is not a failure point, as the cause of `wisent_errors.envelope.build`
 * it is and the values that cause names, or null when it is one.
 */
export function pointFlaw(point) {
  const segments = point.split('.');
  const shared = { quoted_point: JSON.stringify(point), segments: JSON.stringify(segments), suggestion: suggest(point) };
  for (const [index, segment] of segments.entries()) {
    const at = { ...shared, position: String(index + 1), quoted_segment: JSON.stringify(segment) };
    if (segment === '') return { cause: 'failure-point-segment-empty', values: at };
    const characters = [...segment];
    if (!LETTER.test(characters[0])) return { cause: 'failure-point-segment-start', values: { ...at, quoted_character: JSON.stringify(characters[0]) } };
    const outside = characters.find((character) => !ALLOWED.test(character));
    if (outside !== undefined) return { cause: 'failure-point-character', values: { ...at, quoted_character: JSON.stringify(outside) } };
    if (/[-_]$/.test(segment) || /[-_][-_]/.test(segment)) return { cause: 'failure-point-separator', values: at };
  }
  return null;
}

const kindOf = (value) => (value === null ? 'null' : value === undefined ? 'undefined' : Array.isArray(value) ? 'a list' : `of type ${typeof value}`);
const shown = (value) => {
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
};

/** Refuse a field that is not text, naming what it is. */
function requireText(value, field, point) {
  if (typeof value !== 'string') raiseDeclared(ENVELOPE_BUILD, 'field-not-text', { point, field, kind: kindOf(value), shown: shown(value) });
  return value.trim();
}

/** The checks `failure()` makes, in order, each refusing with its declared cause. */
export function checkedEnvelopeFields({ failurePoint, code, service, detail }) {
  const fallback = 'failureOrFallback';
  const point = requireText(failurePoint, 'failurePoint', String(failurePoint));
  const where = point || JSON.stringify(failurePoint);
  if (!point) {
    raiseDeclared(ENVELOPE_BUILD, 'failure-point-absent', { service: String(service), quoted_point: JSON.stringify(failurePoint), fallback });
  }
  const flaw = pointFlaw(point);
  if (flaw !== null) raiseDeclared(ENVELOPE_BUILD, flaw.cause, { ...flaw.values, service: String(service), fallback });
  if (!CODES.includes(code)) {
    raiseDeclared(ENVELOPE_BUILD, 'code-off-catalogue', { point: where, quoted_code: JSON.stringify(code) ?? String(code), codes: CODES.join(', '), coerce: 'codeOrFallback' });
  }
  const named = requireText(service, 'service', where);
  if (!named) raiseDeclared(ENVELOPE_BUILD, 'service-absent', { point: where, quoted_service: JSON.stringify(service), fallback });
  let text = null;
  if (detail !== undefined && detail !== null) {
    text = requireText(detail, 'detail', where);
    if (!text) raiseDeclared(ENVELOPE_BUILD, 'detail-blank', { point: where, quoted_detail: JSON.stringify(detail) });
  }
  return { point, service: named, detail: text };
}
