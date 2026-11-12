"""The ``{name}`` templates a cause or a warning is written in.

How the renderer reads them, and what in them it would never fill, the same
way the Rust, JavaScript and Swift runtimes read them. A template is read left
to right. ``{`` opens a placeholder that the next ``}`` closes, unless another
``{`` comes first: then the first ``{`` never closes. What lies between the
braces is a placeholder when it is a name (PLACEHOLDER_PATTERN); anything else
there (``{value:?}``, ``{Path}``) is kept as written and never filled. A ``}``
no ``{`` opened is kept as written.
"""

from __future__ import annotations

import json
import re
from typing import List, Mapping, Sequence, Tuple

from .declaration import PLACEHOLDER_GRAMMAR, PLACEHOLDER_PATTERN, RAW_MESSAGE_NAMES, SENTENCES

_NAME = re.compile(PLACEHOLDER_PATTERN)

Part = Tuple[str, str]
"""``(kind, text)``: kind is text, placeholder, malformed, unclosed or unopened."""


def quote(text: str) -> str:
    """JSON quoting, as the other runtimes quote a value in a sentence."""
    return json.dumps(text, ensure_ascii=False)


def is_placeholder_name(name: str) -> bool:
    return name.isascii() and _NAME.fullmatch(name) is not None


def parts(template: str) -> List[Part]:
    found: List[Part] = []
    text = ""
    index = 0
    while index < len(template):
        character = template[index]
        if character not in "{}":
            text += character
            index += 1
            continue
        if text:
            found.append(("text", text))
            text = ""
        if character == "}":
            found.append(("unopened", "}"))
            index += 1
            continue
        close = template.find("}", index + 1)
        reopen = template.find("{", index + 1)
        if close >= 0 and (reopen < 0 or close < reopen):
            inside = template[index + 1 : close]
            found.append(("placeholder", inside) if is_placeholder_name(inside) else ("malformed", template[index : close + 1]))
            index = close + 1
        else:
            end = len(template) if reopen < 0 else reopen
            found.append(("unclosed", template[index:end]))
            index = end
    if text:
        found.append(("text", text))
    return found


def fill(template: str, values: Mapping[str, object]) -> str:
    """``template`` with each ``{name}`` replaced by its value; one with no value stays as written."""
    out = []
    for kind, text in parts(template):
        if kind == "placeholder":
            out.append(str(values[text]) if text in values else "{" + text + "}")
        else:
            out.append(text)
    return "".join(out)


def placeholders(template: str) -> List[str]:
    return [text for kind, text in parts(template) if kind == "placeholder"]


def unfilled(templates: Sequence[str], values: Mapping[str, object]) -> List[str]:
    missing: List[str] = []
    for template in templates:
        for name in placeholders(template):
            if name not in values and name not in missing:
                missing.append(name)
    return missing


def suggestion(malformed: str) -> str:
    inside = re.split(r"[:!]", malformed[1:-1])[0].lower()
    name = re.sub(r"^[^a-z]+", "", re.sub(r"[^a-z0-9_]", "_", inside))
    return "{" + (name or "value") + "}"


def template_problems(kind: str, id: str, field: str, template: str) -> List[str]:
    """Everything in one field's template the renderer would never fill or a reader would never be helped by."""
    base = {"kind": kind, "id": id, "field": field}
    problems = []
    read = parts(template)
    for part, text in read:
        if part == "malformed":
            problems.append(fill(SENTENCES["placeholder-malformed"], {**base, "placeholder": text, "grammar": PLACEHOLDER_GRAMMAR, "suggestion": suggestion(text)}))
        elif part == "unclosed":
            problems.append(fill(SENTENCES["placeholder-unclosed"], {**base, "quoted_text": quote(text), "example": "{name}", "open": "{", "close": "}"}))
        elif part == "unopened":
            problems.append(fill(SENTENCES["placeholder-unopened"], {**base, "quoted_text": quote(template), "open": "{", "close": "}"}))
        elif part == "placeholder" and kind == "cause" and field != "observed" and text in RAW_MESSAGE_NAMES:
            problems.append(fill(SENTENCES["placeholder-raw-message"], {**base, "placeholder": "{" + text + "}"}))
    if kind == "cause" and field == "cause":
        wraps = any(part != "text" for part, _ in read)
        words = any(part == "text" and any(character.isalpha() for character in text) for part, text in read)
        if wraps and not words:
            problems.append(fill(SENTENCES["cause-only-wrapped"], {**base, "quoted_text": quote(template)}))
    return problems
