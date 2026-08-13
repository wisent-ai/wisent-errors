"""The failure envelope, for Python components.

Two things only: build an envelope whose derived fields cannot be wrong, and
render it so a reader can find the source. Everything a caller decides -- where
it broke, what the layer below said, which subject it concerns -- is an
argument. Everything derivable from the code is derived.

The ``cause`` chain is the field this package exists for. A gateway refusing a
request because a provider refused a token because a vault refused a read is
three failures; reporting only the outermost is how a day goes into finding
what the innermost already said.
"""

from __future__ import annotations

import json
import re
from typing import Any, Mapping, Optional

from .codes import (
    CODES,
    FAILURE_POINT_PATTERN,
    FALLBACK,
    MEANINGS,
    SEVERITIES,
    from_upstream_status,
    operator_summary,
    outage,
    retryable,
    severity,
)

__all__ = [
    "CODES",
    "FALLBACK",
    "MEANINGS",
    "SEVERITIES",
    "FailureError",
    "chain",
    "failure",
    "from_upstream_status",
    "operator_summary",
    "outage",
    "raise_failure",
    "render",
    "retryable",
    "severity",
]

_FAILURE_POINT = re.compile(FAILURE_POINT_PATTERN)
_DETAIL_LIMIT = 2000


class FailureError(Exception):
    """An exception that carries the envelope rather than replacing it."""

    def __init__(self, envelope: dict[str, Any]) -> None:
        super().__init__(f"{envelope['failure_point']}: {envelope['detail']}")
        self.envelope = envelope


def _trimmed(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise TypeError(f"{field} must be a non-empty string")
    return value.strip()


def failure(
    *,
    failure_point: str,
    code: str,
    service: str,
    impact: str,
    detail: str,
    cause: Optional[Any] = None,
    context: Optional[Mapping[str, Any]] = None,
) -> dict[str, Any]:
    """Build a failure envelope.

    ``detail`` is required on purpose. A failure reported without the reason the
    layer below gave is the defect this package exists to prevent, and making it
    optional is how that defect gets written again.
    """
    point = _trimmed(failure_point, "failure_point")
    if not _FAILURE_POINT.match(point):
        raise TypeError(f"failure_point {point!r} is not <service>.<surface>.<operation>")
    if code not in CODES:
        raise TypeError(f"code {code!r} is not in the catalogue; one of {', '.join(CODES)}")

    envelope: dict[str, Any] = {
        "failure_point": point,
        "error_code": code,
        "service": _trimmed(service, "service"),
        "impact": _trimmed(impact, "impact"),
        "severity": severity(code),
        "retryable": retryable(code),
        "outage": outage(code),
        "detail": _trimmed(detail, "detail")[:_DETAIL_LIMIT],
    }
    if cause is not None:
        envelope["cause"] = cause.envelope if isinstance(cause, FailureError) else dict(cause)
    if context is not None:
        envelope["context"] = dict(context)
    return envelope


def raise_failure(**fields: Any) -> None:
    """The same, raised."""
    raise FailureError(failure(**fields))


def render(envelope: Mapping[str, Any]) -> str:
    """One line for a human, and the envelope for everything else."""
    retry = "; retry later" if envelope["retryable"] else "; retrying will not help"
    whose = "our failure" if envelope["outage"] else "the request or its credentials"
    sentence = f"{operator_summary(envelope['error_code'])} — {whose}{retry}"
    return f"{sentence} {json.dumps(envelope, separators=(',', ':'), ensure_ascii=False)}"


def chain(envelope: Mapping[str, Any]) -> list[str]:
    """Flatten a cause chain, outermost first, for a reader in a hurry."""
    rows: list[str] = []
    node: Optional[Mapping[str, Any]] = envelope
    while node is not None:
        rows.append(f"{node['failure_point']} [{node['error_code']}] {node['detail']}")
        nxt = node.get("cause")
        node = nxt if isinstance(nxt, Mapping) else None
    return rows
