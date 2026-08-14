// Types for the generated catalogue module.
//
// The `/codes` subpath is what a product imports when it wants only the derived
// values and keeps its own renderer, which is most of the fleet.

export type Code = 'config' | 'auth' | 'not_found' | 'rate_limit' | 'timeout' | 'infra_down' | 'unknown';
export type Severity = 'warning' | 'error' | 'critical';

export interface Meaning {
  operatorSummary: string;
  retryable: boolean;
  outage: boolean;
  severity: Severity;
  httpStatus: number;
}

export declare const MEANINGS: Readonly<Record<Code, Meaning>>;
export declare const CODES: readonly Code[];
export declare const SEVERITIES: readonly Severity[];
export declare const FALLBACK: Code;
export declare const FAILURE_POINT_PATTERN: string;
export declare const RETRY_EXIT: number;

export declare function operatorSummary(code: Code): string;
export declare function retryable(code: Code): boolean;
export declare function outage(code: Code): boolean;
export declare function severity(code: Code): Severity;
export declare function codeOrFallback(code: unknown): Code;

/** Whether the catalogue knows this text. A wire boundary needs the question, not a coercion. */
export declare function isCode(code: unknown): code is Code;

/** The code when the catalogue knows this text, otherwise null. */
export declare function codeOrNull(code: unknown): Code | null;
export declare function httpStatus(code: Code): number;
export declare function exitCode(code: Code, chosen: number): number;
export declare function fromUpstreamStatus(status: number): Code;
