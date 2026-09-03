// Generated from catalogue/codes.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

export const MEANINGS = Object.freeze({
  config: {
    operatorSummary: "our deployment configuration is incomplete or wrong",
    retryable: false,
    outage: true,
    severity: "critical",
    httpStatus: 503,
  },
  auth: {
    operatorSummary: "the credentials this command used were rejected",
    retryable: false,
    outage: false,
    severity: "warning",
    httpStatus: 401,
  },
  not_found: {
    operatorSummary: "what the command asked for is not there",
    retryable: false,
    outage: false,
    severity: "warning",
    httpStatus: 404,
  },
  rate_limit: {
    operatorSummary: "an upstream is throttling us",
    retryable: true,
    outage: false,
    severity: "warning",
    httpStatus: 429,
  },
  timeout: {
    operatorSummary: "an upstream did not answer in time",
    retryable: true,
    outage: true,
    severity: "error",
    httpStatus: 504,
  },
  infra_down: {
    operatorSummary: "infrastructure we depend on is unreachable",
    retryable: true,
    outage: true,
    severity: "critical",
    httpStatus: 503,
  },
  refused: {
    operatorSummary: "an explicit policy refused this command",
    retryable: false,
    outage: false,
    severity: "warning",
    httpStatus: 403,
  },
  unknown: {
    operatorSummary: "the command failed and we could not attribute the failure",
    retryable: false,
    outage: false,
    severity: "error",
    httpStatus: 500,
  },
});

export const CODES = Object.freeze(Object.keys(MEANINGS));

// Membership goes through a Set, never `in` or a bare property read. `"toString"
// in MEANINGS` is true, and `__proto__` reads through the prototype chain, so the
// `in` form accepted toString, constructor, hasOwnProperty and valueOf as codes --
// at precisely the wire boundary these predicates exist to guard. weles-web-blog
// had the same hole locally and rendered a failure notice whose headline was `{}`.
const KNOWN = new Set(CODES);
export const SEVERITIES = Object.freeze(["warning","error","critical"]);
export const FALLBACK = "unknown";
export const FAILURE_POINT_PATTERN = "^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*)*$";

/** EX_UNAVAILABLE. retryable codes exit with `retry`; every other code keeps the exit code the caller already chose. */
export const RETRY_EXIT = 69;

const EXACT_STATUS = Object.freeze({
  401: "auth",
  403: "auth",
  404: "not_found",
  407: "auth",
  408: "timeout",
  410: "not_found",
  429: "rate_limit",
  501: "config",
  504: "timeout",
  505: "config",
});

const STATUS_RANGES = Object.freeze([
  { from: 500, to: 599, code: "infra_down" },
]);

export const operatorSummary = (code) => MEANINGS[code].operatorSummary;
export const retryable = (code) => MEANINGS[code].retryable;
export const outage = (code) => MEANINGS[code].outage;
export const severity = (code) => MEANINGS[code].severity;

/**
 * The code when the catalogue knows this text, otherwise the fallback.
 *
 * Never throws. Three products wrote this coercion by hand during their
 * migration, which is the duplication this package exists to remove.
 */
export const codeOrFallback = (code) => (isCode(code) ? code : FALLBACK);

/**
 * Whether the catalogue knows this text at all.
 *
 * Declared as a type guard for TypeScript. A wire boundary has to keep "nothing
 * was declared" apart from "something unknown was declared", because only the
 * first may fall through to the status, and codeOrFallback collapses both.
 */
export const isCode = (code) => typeof code === 'string' && KNOWN.has(code);

/** The code when the catalogue knows this text, otherwise null. */
export const codeOrNull = (code) => (isCode(code) ? code : null);

/** The HTTP status a service answers with when this failure reaches its edge. */
export const httpStatus = (code) => MEANINGS[code].httpStatus;

/** The exit code this failure leaves the process with, given the chosen one. */
export const exitCode = (code, chosen) => (MEANINGS[code].retryable ? RETRY_EXIT : chosen);

/** Classify a status an upstream answered one of our calls with. */
export function fromUpstreamStatus(status) {
  const exact = EXACT_STATUS[status];
  if (exact !== undefined) return exact;
  for (const range of STATUS_RANGES) {
    if (status >= range.from && status <= range.to) return range.code;
  }
  return FALLBACK;
}
