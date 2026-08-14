#!/usr/bin/env node
// Turn the catalogue into one generated module per language.
//
// The catalogue is the source of truth and this is the only thing allowed to
// read it at build time. Every runtime gets the same table, so a code's meaning
// cannot drift between languages -- which is exactly what happened when six
// products each kept their own copy and one of them quietly lost the vocabulary.
//
// Generated files are committed. A consumer needs no build step, and CI
// regenerates and fails on any difference, so the copies stay copies.
//
// Usage: node codegen/generate.mjs [--check]

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CATALOGUE = join(ROOT, 'catalogue', 'codes.json');
const CHECK = process.argv.includes('--check');

const catalogue = JSON.parse(readFileSync(CATALOGUE, 'utf8'));
const banner = (comment) => [
  `${comment} Generated from catalogue/codes.json by codegen/generate.mjs.`,
  `${comment} Do not edit: change the catalogue and regenerate.`,
  `${comment} catalogue version ${catalogue.version}`,
].join('\n');

const codes = catalogue.codes;
const exact = Object.entries(catalogue.upstream_status.exact).map(([status, code]) => [Number(status), code]);
const ranges = catalogue.upstream_status.ranges;
const fallback = catalogue.upstream_status.default;

const rustName = (code) => code.split('_').map((part) => part[0].toUpperCase() + part.slice(1)).join('');

function rust() {
  const variants = codes.map((entry) => `    ${rustName(entry.code)},`).join('\n');
  const asStr = codes.map((entry) => `            Self::${rustName(entry.code)} => "${entry.code}",`).join('\n');
  const parse = codes.map((entry) => `            "${entry.code}" => Some(Self::${rustName(entry.code)}),`).join('\n');
  const summary = codes.map((entry) => `            Self::${rustName(entry.code)} => "${entry.operator_summary}",`).join('\n');
  const retryable = codes.filter((entry) => entry.retryable).map((entry) => `Self::${rustName(entry.code)}`).join(' | ');
  const outage = codes.filter((entry) => entry.outage).map((entry) => `Self::${rustName(entry.code)}`).join(' | ');
  const severity = codes.map((entry) => `            Self::${rustName(entry.code)} => Severity::${entry.severity[0].toUpperCase() + entry.severity.slice(1)},`).join('\n');
  const statusArms = exact.map(([status, code]) => `            ${status} => Self::${rustName(code)},`).join('\n');
  const httpStatus = codes.map((entry) => `            Self::${rustName(entry.code)} => ${entry.http_status},`).join('\n');
  const rangeArms = ranges
    .map((range) => `        if (${range.from}..=${range.to}).contains(&status) {\n            return Self::${rustName(range.code)};\n        }`)
    .join('\n');

  return `${banner('//')}

use std::fmt;

/// How loud this failure is. Derived from the code, never chosen at a call site.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Warning,
    Error,
    Critical,
}

impl Severity {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Warning => "warning",
            Self::Error => "error",
            Self::Critical => "critical",
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// The fleet's whole failure vocabulary.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq, PartialOrd, Ord)]
pub enum Code {
${variants}
}

impl Code {
    /// The exit code a retryable failure leaves the process with.
    ///
    /// ${catalogue.exit_code.retry_name} on every platform this fleet runs on.
    pub const RETRY_EXIT: i32 = ${catalogue.exit_code.retry};

    pub const ALL: &'static [Self] = &[${codes.map((entry) => `Self::${rustName(entry.code)}`).join(', ')}];

    pub fn as_str(self) -> &'static str {
        match self {
${asStr}
        }
    }

    pub fn parse(text: &str) -> Option<Self> {
        match text {
${parse}
            _ => None,
        }
    }

    /// The code when the catalogue knows this text, otherwise the fallback.
    ///
    /// Never fails. Three products wrote this coercion by hand during their
    /// migration, which is the duplication this package exists to remove.
    pub fn or_fallback(text: &str) -> Self {
        match Self::parse(text) {
            Some(code) => code,
            None => Self::${rustName(fallback)},
        }
    }

    /// One sentence for the human who just ran the command: ours or theirs?
    pub fn operator_summary(self) -> &'static str {
        match self {
${summary}
        }
    }

    /// Worth running the same thing again without changing anything.
    pub fn retryable(self) -> bool {
        matches!(self, ${retryable})
    }

    /// Our side is broken, as opposed to the request being wrong.
    pub fn outage(self) -> bool {
        matches!(self, ${outage})
    }

    pub fn severity(self) -> Severity {
        match self {
${severity}
        }
    }

    /// Classify a status an upstream answered one of our calls with.
    pub fn from_upstream_status(status: u16) -> Self {
        match status {
${statusArms}
            _ => {
${rangeArms}
                Self::${rustName(fallback)}
            }
        }
    }

    /// The HTTP status a service answers with when this failure reaches its edge.
    pub fn http_status(self) -> u16 {
        match self {
${httpStatus}
        }
    }

    /// The exit code this failure leaves the process with, given the one the
    /// caller already chose. ${catalogue.exit_code.rule}.
    pub fn exit_code(self, chosen: i32) -> i32 {
        if self.retryable() {
            Self::RETRY_EXIT
        } else {
            chosen
        }
    }
}

impl fmt::Display for Code {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}
`;
}

function python() {
  const rows = codes
    .map(
      (entry) =>
        `    "${entry.code}": _Meaning(\n` +
        `        operator_summary=${JSON.stringify(entry.operator_summary)},\n` +
        `        retryable=${entry.retryable ? 'True' : 'False'},\n` +
        `        outage=${entry.outage ? 'True' : 'False'},\n` +
        `        severity=${JSON.stringify(entry.severity)},\n` +
        `        http_status=${entry.http_status},\n` +
        `    ),`,
    )
    .join('\n');
  const exactRows = exact.map(([status, code]) => `    ${status}: ${JSON.stringify(code)},`).join('\n');
  const rangeRows = ranges
    .map((range) => `    (${range.from}, ${range.to}, ${JSON.stringify(range.code)}),`)
    .join('\n');

  return `${banner('#')}

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class _Meaning:
    operator_summary: str
    retryable: bool
    outage: bool
    severity: str
    http_status: int


MEANINGS: dict[str, _Meaning] = {
${rows}
}

CODES: tuple[str, ...] = tuple(MEANINGS)
SEVERITIES: tuple[str, ...] = ${JSON.stringify(catalogue.severities)}
FALLBACK: str = ${JSON.stringify(fallback)}

# ${catalogue.exit_code.retry_name}. ${catalogue.exit_code.rule}.
RETRY_EXIT: int = ${catalogue.exit_code.retry}

_EXACT_STATUS: dict[int, str] = {
${exactRows}
}

_STATUS_RANGES: tuple[tuple[int, int, str], ...] = (
${rangeRows}
)

FAILURE_POINT_PATTERN: str = ${JSON.stringify(catalogue.failure_point.pattern)}


def operator_summary(code: str) -> str:
    return MEANINGS[code].operator_summary


def retryable(code: str) -> bool:
    return MEANINGS[code].retryable


def outage(code: str) -> bool:
    return MEANINGS[code].outage


def severity(code: str) -> str:
    return MEANINGS[code].severity


def code_or_fallback(text: str) -> str:
    """The code when the catalogue knows this text, otherwise the fallback.

    Never raises. Three products wrote this coercion by hand during their
    migration, which is the duplication this package exists to remove.
    """
    return text if text in MEANINGS else FALLBACK


def http_status(code: str) -> int:
    """The HTTP status a service answers with when this failure reaches its edge."""
    return MEANINGS[code].http_status


def exit_code(code: str, chosen: int) -> int:
    """The exit code this failure leaves the process with, given the chosen one."""
    return RETRY_EXIT if MEANINGS[code].retryable else chosen


def from_upstream_status(status: int) -> str:
    """Classify a status an upstream answered one of our calls with."""
    exact: Optional[str] = _EXACT_STATUS.get(status)
    if exact is not None:
        return exact
    for low, high, code in _STATUS_RANGES:
        if low <= status <= high:
            return code
    return FALLBACK
`;
}

function javascript() {
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
export const codeOrFallback = (code) => (code in MEANINGS ? code : FALLBACK);

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

// Swift, because two native clients hold their own copies: oko-desktop and
// wisent-ios. Cases are camelCase with the catalogue's string as the raw value,
// which is the spelling both already use, so neither has to rename anything.
function swift() {
  const swiftName = (code) =>
    code.split('_').map((part, index) => (index === 0 ? part : part[0].toUpperCase() + part.slice(1))).join('');
  const cases = codes
    .map((entry) =>
      swiftName(entry.code) === entry.code
        ? `    case ${entry.code}`
        : `    case ${swiftName(entry.code)} = "${entry.code}"`,
    )
    .join('\n');
  const arm = (entry, value) => `        case .${swiftName(entry.code)}: ${value}`;
  const severityArms = codes.map((entry) => arm(entry, `.${entry.severity}`)).join('\n');
  const retryableArms = codes.map((entry) => arm(entry, entry.retryable)).join('\n');
  const outageArms = codes.map((entry) => arm(entry, entry.outage)).join('\n');
  const statusArms = codes.map((entry) => arm(entry, entry.http_status)).join('\n');
  const summaryArms = codes.map((entry) => arm(entry, JSON.stringify(entry.operator_summary))).join('\n');
  const exactArms = exact.map(([status, code]) => `        case ${status}: .${swiftName(code)}`).join('\n');
  const rangeArms = ranges
    .map((range) => `        case ${range.from}...${range.to}: .${swiftName(range.code)}`)
    .join('\n');

  return `${banner('//')}

/// How loud this failure is. Derived from the code, never chosen at a call site.
public enum Severity: String, CaseIterable, Sendable, Hashable, Codable {
${catalogue.severities.map((name) => `    case ${name}`).join('\n')}
}

/// The fleet's whole failure vocabulary.
public enum Code: String, CaseIterable, Sendable, Hashable, Codable {
${cases}

    /// The exit code a retryable failure leaves the process with.
    public static let retryExit: Int32 = ${catalogue.exit_code.retry}

    public var severity: Severity {
        switch self {
${severityArms}
        }
    }

    /// Worth running the same thing again without changing anything.
    public var retryable: Bool {
        switch self {
${retryableArms}
        }
    }

    /// Our side is broken, as opposed to the request being wrong.
    public var outage: Bool {
        switch self {
${outageArms}
        }
    }

    /// The HTTP status a service answers with when this failure reaches its edge.
    public var httpStatus: Int {
        switch self {
${statusArms}
        }
    }

    /// One sentence for the human who just ran the command: ours or theirs?
    public var operatorSummary: String {
        switch self {
${summaryArms}
        }
    }

    /// The exit code this failure leaves the process with, given the chosen one.
    public func exitCode(chosen: Int32) -> Int32 {
        retryable ? Self.retryExit : chosen
    }

    /// Classify a status an upstream answered one of our calls with.
    public static func fromUpstream(status: Int) -> Code {
        switch status {
${exactArms}
${rangeArms}
        default: .${swiftName(fallback)}
        }
    }

    /// The code when the catalogue knows this text, otherwise the fallback.
    ///
    /// Never fails. Products wrote this coercion by hand during their migration.
    public static func orFallback(_ text: String?) -> Code {
        guard let text, let code = Code(rawValue: text) else { return .${swiftName(fallback)} }
        return code
    }
}

public let fallbackCode: Code = .${swiftName(fallback)}
public let failurePointPattern = ${JSON.stringify(catalogue.failure_point.pattern)}
`;
}

const targets = [
  { path: join(ROOT, 'rust', 'src', 'codes.rs'), body: rust() },
  { path: join(ROOT, 'python', 'wisent_errors', 'codes.py'), body: python() },
  { path: join(ROOT, 'js', 'codes.mjs'), body: javascript() },
  { path: join(ROOT, 'swift', 'Sources', 'WisentErrors', 'Codes.swift'), body: swift() },
];

let drifted = false;
for (const target of targets) {
  mkdirSync(dirname(target.path), { recursive: true });
  let existing = null;
  try {
    existing = readFileSync(target.path, 'utf8');
  } catch {
    existing = null;
  }
  if (existing === target.body) {
    console.log(`unchanged  ${target.path.slice(ROOT.length + 1)}`);
    continue;
  }
  if (CHECK) {
    drifted = true;
    console.log(`DRIFTED    ${target.path.slice(ROOT.length + 1)}`);
    continue;
  }
  writeFileSync(target.path, target.body);
  console.log(`written    ${target.path.slice(ROOT.length + 1)}`);
}

if (CHECK && drifted) {
  console.log('\ngenerated code does not match the catalogue; run codegen/generate.mjs');
  process.exit(1);
}
