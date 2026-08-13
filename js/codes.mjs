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
  unknown: {
    operatorSummary: "the command failed and we could not attribute the failure",
    retryable: false,
    outage: false,
    severity: "error",
    httpStatus: 500,
  },
});

export const CODES = Object.freeze(Object.keys(MEANINGS));
export const SEVERITIES = Object.freeze(["warning","error","critical"]);
export const FALLBACK = "unknown";
export const FAILURE_POINT_PATTERN = "^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*){2}$";

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
  504: "timeout",
});

const STATUS_RANGES = Object.freeze([
  { from: 500, to: 599, code: "infra_down" },
]);

export const operatorSummary = (code) => MEANINGS[code].operatorSummary;
export const retryable = (code) => MEANINGS[code].retryable;
export const outage = (code) => MEANINGS[code].outage;
export const severity = (code) => MEANINGS[code].severity;

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
