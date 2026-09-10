// Render the JavaScript vocabulary from the generator's prepared catalogue.

export function javascript({ catalogue, codes, exact, ranges, fallback, banner }) {
  const rows = codes
    .map(
      (entry) =>
        `  ${entry.code}: {\n` +
        `    operatorSummary: ${JSON.stringify(entry.operator_summary)},\n` +
        `    retryable: ${entry.retryable},\n` +
        `    outage: ${entry.outage},\n` +
        `    severity: ${JSON.stringify(entry.severity)},\n` +
        `    httpStatus: ${entry.http_status},\n` +
        `  },`,
    )
    .join('\n');
  const exactRows = exact.map(([status, code]) => `  ${status}: ${JSON.stringify(code)},`).join('\n');
  const rangeRows = ranges.map((range) => `  { from: ${range.from}, to: ${range.to}, code: ${JSON.stringify(range.code)} },`).join('\n');

  return `${banner('//')}

export const MEANINGS = Object.freeze({
${rows}
});

export const CODES = Object.freeze(Object.keys(MEANINGS));

// Membership goes through a Set, never \`in\` or a bare property read. \`"toString"
// in MEANINGS\` is true, and \`__proto__\` reads through the prototype chain, so the
// \`in\` form accepted toString, constructor, hasOwnProperty and valueOf as codes --
// at precisely the wire boundary these predicates exist to guard. weles-web-blog
// had the same hole locally and rendered a failure notice whose headline was \`{}\`.
const KNOWN = new Set(CODES);
export const SEVERITIES = Object.freeze(${JSON.stringify(catalogue.severities)});
export const FALLBACK = ${JSON.stringify(fallback)};
export const FAILURE_POINT_PATTERN = ${JSON.stringify(catalogue.failure_point.pattern)};

/** ${catalogue.exit_code.retry_name}. ${catalogue.exit_code.rule}. */
export const RETRY_EXIT = ${catalogue.exit_code.retry};

const EXACT_STATUS = Object.freeze({
${exactRows}
});

const STATUS_RANGES = Object.freeze([
${rangeRows}
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
`;
}

