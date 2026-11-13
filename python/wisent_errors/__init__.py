"""The failure envelope, for Python components.

Two things only: build an envelope whose derived fields cannot be wrong, and
render it so a reader can find the source. Everything a caller decides -- where
it broke, what the layer below said, which subject it concerns -- is an argument.
Everything derivable from the code comes from the catalogue.
"""

from __future__ import annotations

import re
from typing import Any, Mapping, Optional

from .refusal import DeclaredError, checked_envelope_fields, point_flaw
from .operation import Cause, Operation, Warning, catalogue_problems
from .template import fill, placeholders, template_problems, unfilled
from .codes import (
    CODES,
    FAILURE_POINT_PATTERN,
    FALLBACK,
    MEANINGS,
    RETRY_EXIT,
    SEVERITIES,
    code_or_fallback,
    code_or_none,
    exit_code,
    from_upstream_status,
    http_status,
    operator_summary,
    outage,
    retryable,
    severity,
    whose,
)

__all__ = [
    "CODES",
    "FALLBACK",
    "MEANINGS",
    "RETRY_EXIT",
    "SEVERITIES",
    "Cause",
    "DeclaredError",
    "FailureError",
    "Operation",
    "Warning",
    "catalogue_problems",
    "fill",
    "placeholders",
    "point_flaw",
    "template_problems",
    "unfilled",
    "chain",
    "code_or_fallback",
    "code_or_none",
    "exit_code",
    "failure",
    "failure_or_fallback",
    "from_upstream_status",
    "http_status",
    "operator_summary",
    "outage",
    "raise_failure",
    "render",
    "retryable",
    "severity",
    "whose",
]

_FAILURE_POINT = re.compile(FAILURE_POINT_PATTERN)


class FailureError(Exception):
    """A failure carrying its envelope."""

    def __init__(self, envelope: Mapping[str, Any]) -> None:
        detail = envelope.get("detail") or operator_summary(envelope["error_code"])
        super().__init__(f"{envelope['failure_point']}: {detail}")
        self.envelope = dict(envelope)


def _optional(value: Any) -> Optional[str]:
    text = ("" if value is None else str(value)).strip()
    return text or None


def failure(
    *,
    failure_point: str,
    code: str,
    service: str,
    impact: Any = None,
    detail: Any = None,
    remedy: Any = None,
    cause: Optional[Mapping[str, Any]] = None,
    context: Optional[Mapping[str, Any]] = None,
) -> dict:
    """Build a failure envelope.

    ``detail`` and ``impact`` are optional and serialize as ``None`` when absent,
    rather than disappearing: a stable key set is what makes these lines
    queryable in a log store, and three products in this fleet have no impact
    axis at all while two legitimately report a failure with nothing further to
    say. Making either mandatory buys ``impact: "unknown"`` and
    ``detail: "unknown"``, which is a worse lie than an absent value. ``cause``
    and ``context`` are structural and are omitted when there is nothing in them.

    Raises a DeclaredError (a TypeError) on anything malformed, naming the
    declared cause of ``wisent_errors.envelope.build`` and what it found.
    Inside an error path, where raising destroys the diagnosis being carried,
    use :func:`failure_or_fallback`.
    """
    point, named, text = checked_envelope_fields(failure_point, code, service, detail)
    envelope: dict = {
        "failure_point": point,
        "error_code": code,
        "service": named,
        "impact": _optional(impact),
        "severity": severity(code),
        "retryable": retryable(code),
        "outage": outage(code),
        "detail": text,
        "remedy": _optional(remedy),
    }
    if cause is not None:
        envelope["cause"] = dict(cause)
    if context:
        envelope["context"] = dict(context)
    return envelope


def failure_or_fallback(**fields: Any) -> dict:
    """The same, but it never raises.

    Reporting a failure must not itself fail: an error path that dies takes the
    diagnosis with it, which is how hours of an outage end up with no record of
    why. An unknown code becomes the fallback, and anything malformed is recorded
    in ``context`` under a ``wisent_errors.`` key, so the defect travels in the
    data instead of becoming an exception raised inside an ``except``.
    """
    notes: dict = {}

    point = _optional(fields.get("failure_point"))
    if point is None:
        point = "unknown"
        notes["wisent_errors.failure_point"] = "absent"
    elif not _FAILURE_POINT.match(point):
        notes["wisent_errors.failure_point"] = "malformed"
        flaw = point_flaw(point)
        if flaw is not None:
            notes["wisent_errors.failure_point_cause"] = flaw[0]

    code = fields.get("code")
    if not isinstance(code, str) or code not in MEANINGS:
        notes["wisent_errors.error_code"] = "absent" if code is None else f"off-catalogue: {code}"
        code = FALLBACK

    service = _optional(fields.get("service"))
    if service is None:
        notes["wisent_errors.service"] = "absent"

    detail = _optional(fields.get("detail"))
    envelope: dict = {
        "failure_point": point,
        "error_code": code,
        "service": service or "unknown",
        "impact": _optional(fields.get("impact")),
        "severity": severity(code),
        "retryable": retryable(code),
        "outage": outage(code),
        "detail": detail,
        "remedy": _optional(fields.get("remedy")),
    }
    cause = fields.get("cause")
    if cause is not None:
        envelope["cause"] = dict(cause)
    context = dict(fields.get("context") or {})
    context.update(notes)
    if context:
        envelope["context"] = context
    return envelope


def raise_failure(**fields: Any) -> None:
    """The same as :func:`failure`, raised."""
    raise FailureError(failure(**fields))


def render(envelope: Mapping[str, Any]) -> str:
    """One line for a human, and the envelope for everything else.

    The sentence answers the only question that decides what the reader does
    next: ours or theirs. The JSON follows on the same line so grep finds both.
    """
    import json

    retry = "; retry later" if envelope["retryable"] else "; retrying will not help"
    # Whose it is comes from the catalogue, per code: chosen from outage
    # alone, a policy refusal read as a problem with credentials.
    # Rendering a failure must not fail either: a context value JSON has no
    # form for is written as its text.
    body = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False, default=str)
    code = envelope["error_code"]
    return f"{operator_summary(code)} \u2014 {whose(code)}{retry} {body}"


def chain(envelope: Mapping[str, Any]) -> list:
    """Flatten a cause chain, outermost first, for a reader in a hurry."""
    rows = []
    node: Optional[Mapping[str, Any]] = envelope
    while node is not None:
        rows.append(f"{node['failure_point']} [{node['error_code']}] {node.get('detail') or '-'}")
        node = node.get("cause")
    return rows
