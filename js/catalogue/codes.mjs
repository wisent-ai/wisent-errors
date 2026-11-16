// Generated from catalogue/codes.json by codegen/generate.mjs.
// Do not edit: change the catalogue and regenerate.
// catalogue version 1

export const MEANINGS = Object.freeze({
  config: {
    operatorSummary: "our deployment configuration is incomplete or wrong",
    whose: "our failure",
    retryable: false,
    outage: true,
    severity: "critical",
    httpStatus: 503, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  auth: {
    operatorSummary: "the credentials this command used were rejected",
    whose: "the credentials the request presented",
    retryable: false,
    outage: false,
    severity: "warning",
    httpStatus: 401, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  not_found: {
    operatorSummary: "what the command asked for is not there",
    whose: "what the request named",
    retryable: false,
    outage: false,
    severity: "warning",
    httpStatus: 404, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  rate_limit: {
    operatorSummary: "an upstream is throttling us",
    whose: "the pace of the requests, not their content",
    retryable: true,
    outage: false,
    severity: "warning",
    httpStatus: 429, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  timeout: {
    operatorSummary: "an upstream did not answer in time",
    whose: "our failure",
    retryable: true,
    outage: true,
    severity: "error",
    httpStatus: 504, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  infra_down: {
    operatorSummary: "infrastructure we depend on is unreachable",
    whose: "our failure",
    retryable: true,
    outage: true,
    severity: "critical",
    httpStatus: 503, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  refused: {
    operatorSummary: "an explicit policy refused this command",
    whose: "a rule we wrote, not the request's credentials",
    retryable: false,
    outage: false,
    severity: "warning",
    httpStatus: 403, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  },
  unknown: {
    operatorSummary: "the command failed and we could not attribute the failure",
    whose: "not yet attributed to either side",
    retryable: false,
    outage: false,
    severity: "error",
    httpStatus: 500, // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
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
export const RETRY_EXIT = 69; // https://man.freebsd.org/cgi/man.cgi?query=sysexits

/** the clap and click usage code: a request refused for its own form. Never retryable. */
export const USAGE_EXIT = 2; // https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit

/** Wording that says a failure happened without saying which; matched case-insensitively in string literals. */
export const GENERIC_SENTENCES = Object.freeze([
  {
    "text": "did not succeed",
    "reason": "says the operation failed without the step, the cause or the fix"
  },
  {
    "text": "was not successful",
    "reason": "says the operation failed without the step, the cause or the fix"
  },
  {
    "text": "operation failed",
    "reason": "names no operation step and no cause"
  },
  {
    "text": "something went wrong",
    "reason": "names nothing that went wrong"
  },
  {
    "text": "an error occurred",
    "reason": "names no error"
  },
  {
    "text": "unexpected error",
    "reason": "a failure nobody declared: declare its cause instead"
  },
  {
    "text": "unknown error",
    "reason": "a failure nobody classified: declare its cause instead"
  },
  {
    "text": "internal error",
    "reason": "names no component and no cause"
  },
  {
    "text": "please try again",
    "reason": "advises a retry without saying whether a retry can help"
  },
  {
    "text": "failed for an unknown reason",
    "reason": "a failure nobody classified: declare its cause instead"
  },
  {
    "text": "unknown failure",
    "reason": "a failure nobody classified: declare its cause instead"
  },
  {
    "text": "try again later",
    "reason": "advises a later retry without saying when, or what has to change before it can work"
  },
  {
    "text": "could not be completed.",
    "reason": "ends the sentence at the failure: says a step failed and stops before its cause"
  }
]);

const EXACT_STATUS = Object.freeze({
  401: "auth", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  402: "auth", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  403: "auth", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  404: "not_found", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  407: "auth", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  408: "timeout", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  410: "not_found", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  429: "rate_limit", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  501: "config", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  504: "timeout", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  505: "config", // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
});

const STATUS_RANGES = Object.freeze([
  { from: 500, to: 599, code: "infra_down" }, // https://www.rfc-editor.org/rfc/rfc9110.html#section-15
]);

export const operatorSummary = (code) => MEANINGS[code].operatorSummary;
/** Whose the failure is, in the words a rendered line says after the summary. */
export const whose = (code) => MEANINGS[code].whose;
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
