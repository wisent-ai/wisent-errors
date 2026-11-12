# Generated from catalogue/codes.json by codegen/generate.mjs.
# Do not edit: change the catalogue and regenerate.
# catalogue version 1

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class _Meaning:
    operator_summary: str
    whose: str
    retryable: bool
    outage: bool
    severity: str
    http_status: int


MEANINGS: dict[str, _Meaning] = {
    "config": _Meaning(
        operator_summary="our deployment configuration is incomplete or wrong",
        whose="our failure",
        retryable=False,
        outage=True,
        severity="critical",
        http_status=503,
    ),
    "auth": _Meaning(
        operator_summary="the credentials this command used were rejected",
        whose="the credentials the request presented",
        retryable=False,
        outage=False,
        severity="warning",
        http_status=401,
    ),
    "not_found": _Meaning(
        operator_summary="what the command asked for is not there",
        whose="what the request named",
        retryable=False,
        outage=False,
        severity="warning",
        http_status=404,
    ),
    "rate_limit": _Meaning(
        operator_summary="an upstream is throttling us",
        whose="the pace of the requests, not their content",
        retryable=True,
        outage=False,
        severity="warning",
        http_status=429,
    ),
    "timeout": _Meaning(
        operator_summary="an upstream did not answer in time",
        whose="our failure",
        retryable=True,
        outage=True,
        severity="error",
        http_status=504,
    ),
    "infra_down": _Meaning(
        operator_summary="infrastructure we depend on is unreachable",
        whose="our failure",
        retryable=True,
        outage=True,
        severity="critical",
        http_status=503,
    ),
    "refused": _Meaning(
        operator_summary="an explicit policy refused this command",
        whose="a rule we wrote, not the request's credentials",
        retryable=False,
        outage=False,
        severity="warning",
        http_status=403,
    ),
    "unknown": _Meaning(
        operator_summary="the command failed and we could not attribute the failure",
        whose="not yet attributed to either side",
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

# the clap and click usage code: a request refused for its own form. Never retryable.
USAGE_EXIT: int = 2

_EXACT_STATUS: dict[int, str] = {
    401: "auth",
    402: "auth",
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

# Wording that says a failure happened without saying which; matched case-insensitively in string literals.
GENERIC_SENTENCES: tuple = (
    {"text": "did not succeed", "reason": "says the operation failed without the step, the cause or the fix"},
    {"text": "was not successful", "reason": "says the operation failed without the step, the cause or the fix"},
    {"text": "operation failed", "reason": "names no operation step and no cause"},
    {"text": "something went wrong", "reason": "names nothing that went wrong"},
    {"text": "an error occurred", "reason": "names no error"},
    {"text": "unexpected error", "reason": "a failure nobody declared: declare its cause instead"},
    {"text": "unknown error", "reason": "a failure nobody classified: declare its cause instead"},
    {"text": "internal error", "reason": "names no component and no cause"},
    {"text": "please try again", "reason": "advises a retry without saying whether a retry can help"},
    {"text": "failed for an unknown reason", "reason": "a failure nobody classified: declare its cause instead"},
    {"text": "unknown failure", "reason": "a failure nobody classified: declare its cause instead"},
    {"text": "try again later", "reason": "advises a later retry without saying when, or what has to change before it can work"},
    {"text": "could not be completed.", "reason": "ends the sentence at the failure: says a step failed and stops before its cause"},
)


def operator_summary(code: str) -> str:
    return MEANINGS[code].operator_summary


def whose(code: str) -> str:
    """Whose the failure is, in the words a rendered line says after the summary."""
    return MEANINGS[code].whose


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
