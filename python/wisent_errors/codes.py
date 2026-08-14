# Generated from catalogue/codes.json by codegen/generate.mjs.
# Do not edit: change the catalogue and regenerate.
# catalogue version 1

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
    "config": _Meaning(
        operator_summary="our deployment configuration is incomplete or wrong",
        retryable=False,
        outage=True,
        severity="critical",
        http_status=503,
    ),
    "auth": _Meaning(
        operator_summary="the credentials this command used were rejected",
        retryable=False,
        outage=False,
        severity="warning",
        http_status=401,
    ),
    "not_found": _Meaning(
        operator_summary="what the command asked for is not there",
        retryable=False,
        outage=False,
        severity="warning",
        http_status=404,
    ),
    "rate_limit": _Meaning(
        operator_summary="an upstream is throttling us",
        retryable=True,
        outage=False,
        severity="warning",
        http_status=429,
    ),
    "timeout": _Meaning(
        operator_summary="an upstream did not answer in time",
        retryable=True,
        outage=True,
        severity="error",
        http_status=504,
    ),
    "infra_down": _Meaning(
        operator_summary="infrastructure we depend on is unreachable",
        retryable=True,
        outage=True,
        severity="critical",
        http_status=503,
    ),
    "unknown": _Meaning(
        operator_summary="the command failed and we could not attribute the failure",
        retryable=False,
        outage=False,
        severity="error",
        http_status=500,
    ),
}

CODES: tuple[str, ...] = tuple(MEANINGS)
SEVERITIES: tuple[str, ...] = ["warning","error","critical"]
FALLBACK: str = "unknown"

# EX_UNAVAILABLE. retryable codes exit with `retry`; every other code keeps the exit code the caller already chose.
RETRY_EXIT: int = 69

_EXACT_STATUS: dict[int, str] = {
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
}

_STATUS_RANGES: tuple[tuple[int, int, str], ...] = (
    (500, 599, "infra_down"),
)

FAILURE_POINT_PATTERN: str = "^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*)*$"


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
