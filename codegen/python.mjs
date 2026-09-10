// Render the Python vocabulary from the generator's prepared catalogue.

export function python({ catalogue, codes, exact, ranges, fallback, banner }) {
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


def code_or_none(text: str) -> Optional[str]:
    """The code when the catalogue knows this text, otherwise None.

    The honest primitive at a wire boundary, where "nothing was declared" and
    "something unknown was declared" must stay apart: only the first may fall
    through to a status. Four TypeScript consumers hit that boundary and two asked
    for this within an hour of each other.
    """
    return text if text in CODES else None


def code_or_fallback(text: str) -> str:
    """The code when the catalogue knows this text, otherwise the fallback.

    Never raises. Three products wrote this coercion by hand during their
    migration, which is the duplication this package exists to remove.
    """
    return text if text in CODES else FALLBACK


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

