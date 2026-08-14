"""The failure envelope, for Python components.

Two things only: build an envelope whose derived fields cannot be wrong, and
render it so a reader can find the source. Everything a caller decides -- where
it broke, what the layer below said, which subject it concerns -- is an argument.
Everything derivable from the code comes from the catalogue.
"""

from __future__ import annotations

import re
from typing import Any, Mapping, Optional

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
)

__all__ = [
    "CODES",
    "DETAIL_LIMIT",
    "FALLBACK",
    "MEANINGS",
    "RETRY_EXIT",
    "SEVERITIES",
    "FailureError",
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
    "trim_detail",
    "trim_detail_at_word_edge",
]

_FAILURE_POINT = re.compile(FAILURE_POINT_PATTERN)

#: This package's own bound. A product's bound is the product's to choose.
DETAIL_LIMIT = 2000


def trim_detail(text: Any, limit: int = DETAIL_LIMIT) -> str:
    """Trim a detail to a bound. A hard cut, which is what the fleet emits.

    The limit is an argument because the width is a product's own decision --
    stado and probierz keep 300, wisent-customer-support 400, wisent-tools 500 --
    while the rule for how to cut is the thing that was written six times.

    An earlier version of this backed up to the last word edge within 24
    characters of the bound. Nothing in the fleet did that: four products cut
    hard, and adopting the nicer rule silently moved the bytes of an
    operator-visible line for every detail longer than the bound that contains a
    space. Ends are still stripped, because whitespace around a detail is never
    information.
    """
    value = ("" if text is None else str(text)).strip()
    return value if len(value) <= limit else value[:limit]


def trim_detail_at_word_edge(text: Any, limit: int = DETAIL_LIMIT, slack: int = 24) -> str:
    """The same, cut back to a word edge when one falls within ``slack`` of the bound.

    Separate and opt-in, because it changes emitted bytes.
    """
    value = ("" if text is None else str(text)).strip()
    cut = trim_detail(value, limit)
    if len(cut) < limit:
        return cut
    if value[limit].isspace():
        return cut.rstrip()
    # ``edge > 0`` matters: rfind returns -1 when there is no space at all, and for
    # any limit under ``slack`` that -1 passes a bare ``edge > limit - slack``, which
    # silently dropped the last character. No fleet width is that small; the guard
    # was still wrong rather than benignly unreachable.
    edge = cut.rfind(" ")
    return (cut[:edge] if edge > 0 and edge > limit - slack else cut).rstrip()


class FailureError(Exception):
    """A failure carrying its envelope."""

    def __init__(self, envelope: Mapping[str, Any]) -> None:
        detail = envelope.get("detail") or operator_summary(envelope["error_code"])
        super().__init__(f"{envelope['failure_point']}: {detail}")
        self.envelope = dict(envelope)


def _required(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise TypeError(f"{field} must be a non-empty string")
    return value.strip()


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

    Raises on anything malformed. Inside an error path, where raising destroys
    the diagnosis being carried, use :func:`failure_or_fallback`.
    """
    point = _required(failure_point, "failure_point")
    if not _FAILURE_POINT.match(point):
        raise TypeError(f"failure_point {point!r} is not a dotted lowercase path")
    if code not in MEANINGS:
        raise TypeError(f"code {code!r} is not in the catalogue; one of {', '.join(CODES)}")

    envelope: dict = {
        "failure_point": point,
        "error_code": code,
        "service": _required(service, "service"),
        "impact": _optional(impact),
        "severity": severity(code),
        "retryable": retryable(code),
        "outage": outage(code),
        "detail": None if detail is None else trim_detail(_required(detail, "detail"), DETAIL_LIMIT),
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
        "detail": None if detail is None else trim_detail(detail, DETAIL_LIMIT),
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
    whose = "our failure" if envelope["outage"] else "the request or its credentials"
    body = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    return f"{operator_summary(envelope['error_code'])} \u2014 {whose}{retry} {body}"


def chain(envelope: Mapping[str, Any]) -> list:
    """Flatten a cause chain, outermost first, for a reader in a hurry."""
    rows = []
    node: Optional[Mapping[str, Any]] = envelope
    while node is not None:
        rows.append(f"{node['failure_point']} [{node['error_code']}] {node.get('detail') or '-'}")
        node = node.get("cause")
    return rows
