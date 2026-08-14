// Types for the failure envelope.
//
// Hand-written rather than generated, because the generated module is the
// catalogue and this is the shape of the runtime around it. Four of the fleet's
// TypeScript consumers cannot adopt the package without these, which is why they
// exist at all: a package every product has to adopt must be cheap to adopt, and
// for a TypeScript app "cheap" means it type-checks.

export type Code = 'config' | 'auth' | 'not_found' | 'rate_limit' | 'timeout' | 'infra_down' | 'unknown';
export type Severity = 'warning' | 'error' | 'critical';

/** Identifiers a reader needs to find the subject: a host, a subscription, a job. */
export type Context = Record<string, string | number | boolean | null>;

/**
 * One failure, in the shape every Wisent component reports.
 *
 * `impact` and `detail` are present and `null` when there is nothing to say, so a
 * log store keeps a stable key set. `cause` and `context` are structural and
 * absent when empty.
 */
export interface Envelope {
  failure_point: string;
  error_code: Code;
  service: string;
  impact: string | null;
  severity: Severity;
  retryable: boolean;
  outage: boolean;
  detail: string | null;
  cause?: Envelope;
  context?: Context;
}

export interface Fields {
  failurePoint: string;
  code: Code;
  service: string;
  impact?: string | null;
  detail?: string | null;
  cause?: Envelope | FailureError | null;
  context?: Context | null;
}

/** The fields the never-throwing builder accepts: anything, by design. */
export interface SalvageableFields {
  failurePoint?: unknown;
  code?: unknown;
  service?: unknown;
  impact?: unknown;
  detail?: unknown;
  cause?: Envelope | FailureError | null;
  context?: Context | null;
}

export declare class FailureError extends Error {
  constructor(envelope: Envelope);
  readonly name: 'FailureError';
  readonly envelope: Envelope;
}

/** Throws on anything malformed. On an error path, use `failureOrFallback`. */
export declare function failure(fields: Fields): Envelope;

/** Never throws. Records each violation in `context` under a `wisent_errors.` key. */
export declare function failureOrFallback(fields?: SalvageableFields): Envelope;

/** The same as `failure`, thrown. */
export declare function raise(fields: Fields): never;

/** One line for a human, and the envelope for everything else. */
export declare function render(envelope: Envelope): string;

/** Flatten a cause chain, outermost first. */
export declare function chain(envelope: Envelope): string[];

/** A hard cut, which is what the fleet emits. The width is yours. */
export declare function trimDetail(text: unknown, limit?: number): string;

/** Cut back to a word edge when one falls within `slack`. Opt-in: it moves bytes. */
export declare function trimDetailAtWordEdge(text: unknown, limit?: number, slack?: number): string;

/** The code when the catalogue knows it, otherwise the fallback. Never throws. */
export declare function codeOrFallback(text: unknown): Code;

/** Whether the catalogue knows this text. A wire boundary needs the question, not a coercion. */
export declare function isCode(text: unknown): text is Code;

/** The code when the catalogue knows this text, otherwise null. */
export declare function codeOrNull(text: unknown): Code | null;

export declare function operatorSummary(code: Code): string;
export declare function severity(code: Code): Severity;
export declare function retryable(code: Code): boolean;
export declare function outage(code: Code): boolean;
export declare function httpStatus(code: Code): number;
export declare function exitCode(code: Code, chosen: number): number;
export declare function fromUpstreamStatus(status: number): Code;

export declare const CODES: readonly Code[];
export declare const SEVERITIES: readonly Severity[];
export declare const MEANINGS: Readonly<
  Record<Code, { operatorSummary: string; retryable: boolean; outage: boolean; severity: Severity; httpStatus: number }>
>;
export declare const FALLBACK: Code;
export declare const FAILURE_POINT_PATTERN: string;
export declare const RETRY_EXIT: number;
export declare const DETAIL_LIMIT: number;
