#!/usr/bin/env python3
"""The Python run from docs/integrate/python.md, runnable from a checkout:

    python3 docs/examples/first_envelope.py

A real consumer installs the package (pinned to a commit, see
docs/quick-start.md); this script puts python/ on the path so it needs no pip
install.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from wisent_errors import failure, failure_or_fallback, render, chain, trim_detail
from wisent_errors.codes import from_upstream_status, exit_code, code_or_none, RETRY_EXIT

refused = failure(
    failure_point="toy.vault.read",
    code="infra_down",
    service="toy",
    detail="connection refused (127.0.0.1:9700)",
)
envelope = failure(
    failure_point="toy.job.credentials",
    code="infra_down",
    service="toy",
    impact="every job this worker claims",
    detail="secret resolution failed",
    cause=refused,
    context={"job": "j-3f21"},
)
print("render:", render(envelope))
for row in chain(envelope):
    print("  " + row)

print("from_upstream_status(407):", from_upstream_status(407))
print("from_upstream_status(501):", from_upstream_status(501))
print(f"exit_code('infra_down', 3): {exit_code('infra_down', 3)} (RETRY_EXIT = {RETRY_EXIT})")
print("exit_code('not_found', 3):", exit_code("not_found", 3))
print("code_or_none('offline'):", code_or_none("offline"))
print("trim_detail('  padded detail  ', 300):", repr(trim_detail("  padded detail  ", 300)))

try:
    failure(failure_point="Not A Point", code="auth", service="toy")
except TypeError as error:
    print("strict refusal:", error)

try:
    failure(failure_point="toy.first", code="panic", service="toy")
except TypeError as error:
    print("strict refusal:", error)

import json

salvaged = failure_or_fallback(code="panic")
print("salvaged:", json.dumps(salvaged, separators=(",", ":"), ensure_ascii=False))
