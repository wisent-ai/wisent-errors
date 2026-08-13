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


MEANINGS: dict[str, _Meaning] = {
    "config": _Meaning(
        operator_summary="our deployment configuration is incomplete or wrong",
        retryable=False,
        outage=True,
        severity="critical",
    ),
    "auth": _Meaning(
        operator_summary="the credentials this command used were rejected",
        retryable=False,
        outage=False,
        severity="warning",
    ),
    "not_found": _Meaning(
        operator_summary="what the command asked for is not there",
        retryable=False,
        outage=False,
        severity="warning",
    ),
    "rate_limit": _Meaning(
        operator_summary="an upstream is throttling us",
        retryable=True,
        outage=False,
        severity="warning",
    ),
    "timeout": _Meaning(
        operator_summary="an upstream did not answer in time",
        retryable=True,
        outage=True,
        severity="error",
    ),
    "infra_down": _Meaning(
        operator_summary="infrastructure we depend on is unreachable",
        retryable=True,
        outage=True,
        severity="critical",
    ),
    "unknown": _Meaning(
        operator_summary="the command failed and we could not attribute the failure",
        retryable=False,
        outage=False,
        severity="error",
    ),
}

CODES: tuple[str, ...] = tuple(MEANINGS)
SEVERITIES: tuple[str, ...] = ["warning","error","critical"]
FALLBACK: str = "unknown"

_EXACT_STATUS: dict[int, str] = {
    401: "auth",
    403: "auth",
    404: "not_found",
    407: "auth",
    408: "timeout",
    410: "not_found",
    429: "rate_limit",
    504: "timeout",
}

_STATUS_RANGES: tuple[tuple[int, int, str], ...] = (
    (500, 599, "infra_down"),
)

FAILURE_POINT_PATTERN: str = "^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*(?:\\.[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*){2}$"


def operator_summary(code: str) -> str:
    return MEANINGS[code].operator_summary


def retryable(code: str) -> bool:
    return MEANINGS[code].retryable


def outage(code: str) -> bool:
    return MEANINGS[code].outage


def severity(code: str) -> str:
    return MEANINGS[code].severity


def from_upstream_status(status: int) -> str:
    """Classify a status an upstream answered one of our calls with."""
    exact: Optional[str] = _EXACT_STATUS.get(status)
    if exact is not None:
        return exact
    for low, high, code in _STATUS_RANGES:
        if low <= status <= high:
            return code
    return FALLBACK
