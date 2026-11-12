"""How this package refuses the calls made to it.

Each refusal is a cause of its own failure catalogue (catalogue/failures/,
generated into ``failures.py``), raised as a DeclaredError naming the
operation, the cause and the values the raising site knew.
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, Mapping, Optional, Tuple

from .codes import CODES
from .failures import ENVELOPE_BUILD
from .operation import Operation

_FALLBACK = "failure_or_fallback"


class DeclaredError(TypeError):
    """A refusal of a declared cause; a TypeError, as the strict builders raised before."""

    def __init__(self, operation: Operation, cause_id: str, values: Mapping[str, object]) -> None:
        cause = operation.cause_named(cause_id)
        super().__init__(cause.refusal(values))
        self.operation = operation.id
        self.cause = cause.id
        self.code = cause.code
        self.values = dict(values)


def _quote(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def suggest(point: str) -> str:
    segments = []
    for segment in point.split("."):
        word = re.sub(r"[^a-z0-9]+", "-", segment.lower())
        word = re.sub(r"-+$", "", re.sub(r"^[^a-z]+", "", word))
        if word:
            segments.append(word)
    return "'" + (".".join(segments) if segments else "stado.fleet.enroll") + "'"


def point_flaw(point: str) -> Optional[Tuple[str, Dict[str, str]]]:
    """The cause of ``wisent_errors.envelope.build`` a malformed point is, with its values; None for a good one."""
    segments = point.split(".")
    shared = {"quoted_point": _quote(point), "segments": _quote(segments), "suggestion": suggest(point)}
    for index, segment in enumerate(segments):
        at = {**shared, "position": str(index + 1), "quoted_segment": _quote(segment)}
        if segment == "":
            return "failure-point-segment-empty", at
        if not ("a" <= segment[0] <= "z"):
            return "failure-point-segment-start", {**at, "quoted_character": _quote(segment[0])}
        outside = next((character for character in segment if not re.fullmatch(r"[a-z0-9_-]", character)), None)
        if outside is not None:
            return "failure-point-character", {**at, "quoted_character": _quote(outside)}
        if re.search(r"[-_]$|[-_][-_]", segment):
            return "failure-point-separator", at
    return None


def _kind(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, (list, tuple)):
        return "a list"
    return f"of type {type(value).__name__}"


def _shown(value: Any) -> str:
    if isinstance(value, BaseException):
        return f"{type(value).__name__}: {value}"
    try:
        return _quote(value)
    except (TypeError, ValueError):
        return repr(value)


def _text(value: Any, field: str, point: str) -> str:
    if not isinstance(value, str):
        raise DeclaredError(ENVELOPE_BUILD, "field-not-text", {"point": point, "field": field, "kind": _kind(value), "shown": _shown(value)})
    return value.strip()


def checked_envelope_fields(failure_point: Any, code: Any, service: Any, detail: Any) -> Tuple[str, str, Optional[str]]:
    """The checks ``failure()`` makes, in order, each refusing with its declared cause."""
    point = _text(failure_point, "failure_point", str(failure_point))
    where = point or _quote(failure_point)
    if not point:
        raise DeclaredError(ENVELOPE_BUILD, "failure-point-absent", {"service": str(service), "quoted_point": _quote(failure_point), "fallback": _FALLBACK})
    flaw = point_flaw(point)
    if flaw is not None:
        raise DeclaredError(ENVELOPE_BUILD, flaw[0], {**flaw[1], "service": str(service), "fallback": _FALLBACK})
    if code not in CODES:
        raise DeclaredError(ENVELOPE_BUILD, "code-off-catalogue", {"point": where, "quoted_code": _shown(code), "codes": ", ".join(CODES), "coerce": "code_or_fallback"})
    named = _text(service, "service", where)
    if not named:
        raise DeclaredError(ENVELOPE_BUILD, "service-absent", {"point": where, "quoted_service": _quote(service), "fallback": _FALLBACK})
    text = None
    if detail is not None:
        text = _text(detail, "detail", where)
        if not text:
            raise DeclaredError(ENVELOPE_BUILD, "detail-blank", {"point": where, "quoted_detail": _quote(detail)})
    return point, named, text
