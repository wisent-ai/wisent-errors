#!/usr/bin/env python3
"""Emit every golden case through the Python runtime, one JSON per line."""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "python"))

from wisent_errors import failure  # noqa: E402  (path set above on purpose)

CASES = pathlib.Path(__file__).resolve().parent / "conformance" / "cases.tsv"


def parse_case(line: str) -> dict[str, str]:
    """Tab separated ``key=value``; the first ``=`` separates, so values may contain more."""
    fields: dict[str, str] = {}
    for pair in line.split("\t"):
        if not pair or "=" not in pair:
            continue
        key, _, value = pair.partition("=")
        fields[key] = value
    return fields


for line in CASES.read_text(encoding="utf-8").splitlines():
    if not line.strip() or line.startswith("#"):
        continue
    fields = parse_case(line)

    cause = None
    if fields.get("cause_failure_point"):
        cause = failure(
            failure_point=fields["cause_failure_point"],
            code=fields["cause_code"],
            service=fields["cause_service"],
            impact=fields["cause_impact"],
            detail=fields["cause_detail"],
        )

    context = None
    if fields.get("context"):
        key, _, value = fields["context"].partition("=")
        context = {key: value}

    envelope = failure(
        failure_point=fields["failure_point"],
        code=fields["code"],
        service=fields["service"],
        impact=fields["impact"],
        detail=fields["detail"],
        cause=cause,
        context=context,
    )
    rendered = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    print(f"{fields['name']}\t{rendered}")
