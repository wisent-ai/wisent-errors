"""A functionality's failure catalogue and warnings, for Python products.

The same declarations the Rust crate's ``operation`` and ``warning`` modules
hold, held to the same rules with the same sentences
(catalogue/declaration.json), printing the same JSON.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

from .codes import CODES, FAILURE_POINT_PATTERN, GENERIC_SENTENCES, RETRY_EXIT, USAGE_EXIT, retryable
from .declaration import CAUSE_ID_PATTERN, FIELD_MEANINGS, SENTENCES, TEST_PATH_PATTERN
from .template import fill, quote, template_problems, unfilled

HAZARDS: Dict[str, str] = {
    "irreversible": "removes or rewrites something nothing in the product restores afterwards",
    "overwrites": "puts something else in place of the current state; what it replaces is kept only where the warning says",
    "cuts-off-access": "a person or a program loses access it has now",
    "exposes-secret": "a secret value leaves the place that protects it: a plain-text file, a screen, another person or system",
    "external-change": "changes a system outside the product, which the product cannot undo",
    "costs-money": "spends money",
}


def _matches(pattern: str, text: Any) -> bool:
    return isinstance(text, str) and re.fullmatch(pattern, text) is not None


def _generic():
    return GENERIC_SENTENCES


def text_problems(kind: str, id: str, fields: Sequence[Tuple[str, Any]]) -> List[str]:
    problems: List[str] = []
    for name, text in fields:
        if not isinstance(text, str) or not text.strip():
            problems.append(fill(SENTENCES["field-empty"], {"kind": kind, "id": id, "field": name, "meaning": FIELD_MEANINGS[name]}))
            continue
        for sentence in _generic():
            if sentence["text"] in text.lower():
                problems.append(fill(SENTENCES["field-generic"], {"kind": kind, "id": id, "field": name, "quoted_text": quote(sentence["text"]), "reason": sentence["reason"]}))
        problems.extend(template_problems(kind, id, name, text))
    return problems


@dataclass(frozen=True)
class Cause:
    """One way an operation can fail; the four sentences are ``{name}`` templates."""

    id: str
    code: str
    failed: str
    cause: str
    observed: str
    remedy: str
    test: str
    usage: bool = False
    exit: Optional[int] = None

    def sentence(self, values: Mapping[str, object]) -> str:
        return f"{fill(self.failed, values)}: {fill(self.cause, values)}; observed: {fill(self.observed, values)}"

    def fix(self, values: Mapping[str, object]) -> str:
        return fill(self.remedy, values)

    def refusal(self, values: Mapping[str, object]) -> str:
        return f"{self.sentence(values)}; fix: {self.fix(values)}"

    def unfilled(self, values: Mapping[str, object]) -> List[str]:
        return unfilled([self.failed, self.cause, self.observed, self.remedy], values)

    def exit_code(self, failure_exit: int) -> int:
        if self.usage:
            return USAGE_EXIT
        if self.exit is not None:
            return self.exit
        return RETRY_EXIT if self.code in CODES and retryable(self.code) else failure_exit

    def problems(self) -> List[str]:
        id = self.id
        problems: List[str] = []
        if not _matches(CAUSE_ID_PATTERN, id):
            problems.append(fill(SENTENCES["id-malformed"], {"kind": "cause", "quoted_id": quote(str(id)), "pattern": CAUSE_ID_PATTERN}))
        problems.extend(text_problems("cause", id, [(name, getattr(self, name)) for name in ("failed", "cause", "observed", "remedy")]))
        codes = ", ".join(code for code in CODES if code != "unknown")
        if self.code not in CODES:
            problems.append(fill(SENTENCES["code-off-catalogue"], {"id": id, "quoted_code": quote(str(self.code)), "codes": codes}))
        elif self.code == "unknown":
            problems.append(fill(SENTENCES["code-unknown"], {"id": id, "codes": codes}))
        elif self.usage and retryable(self.code):
            problems.append(fill(SENTENCES["usage-retryable"], {"id": id, "code": self.code}))
        if self.exit is not None:
            limits = {"id": id, "exit": str(self.exit), "usage_exit": str(USAGE_EXIT), "retry_exit": str(RETRY_EXIT)}
            if self.usage or (self.code in CODES and retryable(self.code)):
                problems.append(fill(SENTENCES["exit-beside-derived"], limits))
            if self.exit in (0, USAGE_EXIT, RETRY_EXIT):
                problems.append(fill(SENTENCES["exit-not-own"], limits))
        if not _matches(TEST_PATH_PATTERN, self.test):
            problems.append(fill(SENTENCES["test-malformed"], {"kind": "cause", "id": id, "quoted_test": quote(str(self.test)), "pattern": TEST_PATH_PATTERN}))
        return problems


@dataclass(frozen=True)
class Warning:
    """One thing a functionality does that its caller must know before it runs."""

    id: str
    hazard: str
    effect: str
    consequence: str
    safeguard: str
    confirm: str
    test: str

    def problems(self) -> List[str]:
        id = self.id
        problems: List[str] = []
        if not _matches(CAUSE_ID_PATTERN, id):
            problems.append(fill(SENTENCES["id-malformed"], {"kind": "warning", "quoted_id": quote(str(id)), "pattern": CAUSE_ID_PATTERN}))
        if self.hazard not in HAZARDS:
            problems.append(fill(SENTENCES["hazard-unknown"], {"id": id, "quoted_hazard": quote(str(self.hazard)), "hazards": ", ".join(HAZARDS)}))
        problems.extend(text_problems("warning", id, [(name, getattr(self, name)) for name in ("effect", "consequence", "safeguard", "confirm")]))
        if not _matches(TEST_PATH_PATTERN, self.test):
            problems.append(fill(SENTENCES["test-malformed"], {"kind": "warning", "id": id, "quoted_test": quote(str(self.test)), "pattern": TEST_PATH_PATTERN}))
        return problems


@dataclass(frozen=True)
class Operation:
    """One functionality, named by its failure point, and every cause of its own steps."""

    id: str
    summary: str
    docs: str
    entries: Tuple[str, ...] = ()
    uses: Tuple["Operation", ...] = ()
    causes: Tuple[Cause, ...] = ()
    warnings: Tuple[Warning, ...] = field(default=())

    @staticmethod
    def from_dict(declared: Mapping[str, Any]) -> "Operation":
        causes = tuple(Cause(**{key: value for key, value in cause.items()}) for cause in declared["causes"])
        return Operation(id=declared["id"], summary=declared["summary"], docs=declared["docs"], entries=tuple(declared["entries"]), causes=causes)

    def cause_named(self, id: str) -> Optional[Cause]:
        return next((cause for cause in self.causes if cause.id == id), None)

    def problems(self) -> List[str]:
        id = self.id
        named = {"operation": id}
        problems: List[str] = []
        if not _matches(FAILURE_POINT_PATTERN, id):
            problems.append(fill(SENTENCES["operation-id-malformed"], {"quoted_id": quote(str(id)), "pattern": FAILURE_POINT_PATTERN}))
        for index, entry in enumerate(self.entries):
            if not isinstance(entry, str) or not entry.strip():
                problems.append(fill(SENTENCES["entry-empty"], {**named, "position": str(index + 1), "count": str(len(self.entries))}))
        if any(used.id == id for used in self.uses):
            problems.append(fill(SENTENCES["uses-itself"], named))
        if not self.summary.strip():
            problems.append(fill(SENTENCES["summary-empty"], named))
        if not self.docs.startswith("https://"):
            problems.append(fill(SENTENCES["docs-not-https"], {**named, "quoted_docs": quote(self.docs)}))
        if not self.causes and not self.uses:
            problems.append(fill(SENTENCES["no-cause"], named))
        for kind, declared in (("cause", self.causes), ("warning", self.warnings)):
            for index, item in enumerate(declared):
                if any(earlier.id == item.id for earlier in declared[:index]):
                    problems.append(fill(SENTENCES["declared-twice"], {**named, "kind": kind, "id": item.id}))
                problems.extend(f"operation {id}: {problem}" for problem in item.problems())
        return problems

    def catalogue(self, failure_exit: int) -> Dict[str, Any]:
        """The JSON document every product prints from ``errors list|show --json``."""
        return {
            "operation": self.id,
            "entries": list(self.entries),
            "uses": [used.id for used in self.uses],
            "summary": self.summary,
            "docs": self.docs,
            "causes": [
                {
                    "id": cause.id, "code": cause.code, "exit": cause.exit_code(failure_exit),
                    "retryable": cause.code in CODES and retryable(cause.code), "usage": cause.usage,
                    "failed": cause.failed, "cause": cause.cause, "observed": cause.observed, "remedy": cause.remedy,
                    "test": cause.test, "doc": f"{self.docs}#{self.id.replace('.', '-')}-{cause.id}",
                }
                for cause in self.causes
            ],
        }


def catalogue_problems(operations: Sequence[Operation]) -> List[str]:
    problems: List[str] = []
    for index, operation in enumerate(operations):
        named = {"operation": operation.id}
        if any(earlier.id == operation.id for earlier in operations[:index]):
            problems.append(fill(SENTENCES["operation-twice"], named))
        for used in operation.uses:
            if not any(listed.id == used.id for listed in operations):
                problems.append(fill(SENTENCES["uses-unlisted"], {**named, "used": used.id}))
        used_by_another = any(any(used.id == operation.id for used in other.uses) for other in operations)
        if not operation.entries and not used_by_another:
            problems.append(fill(SENTENCES["nothing-starts"], named))
    return problems
