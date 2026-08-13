#!/usr/bin/env python3
"""Emit every golden case through the Python runtime, one JSON per line.

With ``--table`` it dumps the whole derived vocabulary instead: every code's
severity, retryability, outage, HTTP status and exit code, plus how each
interesting upstream status classifies. Six envelopes prove the shape; this
proves the table, which is where three copies of an HTTP status map and three
copies of an exit rule used to live.
"""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "python"))

from wisent_errors import (  # noqa: E402
    failure,
    failure_or_fallback,
    trim_detail,
    trim_detail_at_word_edge,
)
from wisent_errors.codes import (  # noqa: E402
    CODES,
    exit_code,
    from_upstream_status,
    http_status,
    operator_summary,
    outage,
    retryable,
    severity,
)

HERE = pathlib.Path(__file__).resolve().parent
CASES = HERE / "conformance" / "cases.tsv"
TABLE = HERE / "conformance" / "table.tsv"


def parse_case(line: str) -> dict[str, str]:
    """Tab separated ``key=value``; the first ``=`` separates, so values may contain more."""
    fields: dict[str, str] = {}
    for pair in line.split("\t"):
        if not pair or "=" not in pair:
            continue
        key, _, value = pair.partition("=")
        fields[key] = value
    return fields


def table_probes() -> tuple[list[int], int, list]:
    """The statuses to classify and the exit code a caller brings, read as data."""
    rows: dict[str, list[str]] = {}
    for line in TABLE.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        rows[fields[0]] = fields[1:]
    trims = [
        (line.split("\t")[0], int(line.split("\t")[1]), line.split("\t")[2])
        for line in TABLE.read_text(encoding="utf-8").splitlines()
        if line.startswith("trim\t") or line.startswith("word\t")
    ]
    return [int(status) for status in rows["statuses"]], int(rows["chosen_exit"][0]), trims


if "--table" in sys.argv:
    statuses, chosen, trims = table_probes()
    for code in CODES:
        print(
            "\t".join(
                (
                    f"code={code}",
                    f"severity={severity(code)}",
                    f"retryable={str(retryable(code)).lower()}",
                    f"outage={str(outage(code)).lower()}",
                    f"http_status={http_status(code)}",
                    f"exit_code={exit_code(code, chosen)}",
                    f"operator_summary={operator_summary(code)}",
                )
            )
        )
    for status in statuses:
        print(f"status={status}\tcode={from_upstream_status(status)}")
    for rule, limit, text in trims:
        cut = trim_detail_at_word_edge(text, limit) if rule == "word" else trim_detail(text, limit)
        print(f"{rule}={limit}\tresult={cut}")
    raise SystemExit(0)


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
            impact=fields.get("cause_impact"),
            detail=fields.get("cause_detail"),
        )

    context = None
    if fields.get("context"):
        key, _, value = fields["context"].partition("=")
        context = {key: value}

    build = failure_or_fallback if fields.get("builder") == "or_fallback" else failure
    envelope = build(
        failure_point=fields["failure_point"],
        code=fields["code"],
        service=fields["service"],
        impact=fields.get("impact"),
        detail=fields.get("detail"),
        cause=cause,
        context=context,
    )
    rendered = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    print(f"{fields['name']}\t{rendered}")
