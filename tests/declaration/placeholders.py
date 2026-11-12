"""Real tests of the declaration rules a Python product's causes are held to.

A placeholder the renderer never fills, a cause that only wraps the raw text
below it, raw text outside ``observed``, and the probes
catalogue/declaration.json states for every runtime.

    python3 tests/declaration/placeholders.py
"""

import sys
import unittest
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from wisent_errors import Cause, fill, unfilled  # noqa: E402
from wisent_errors.declaration import PROBES  # noqa: E402
from wisent_errors.template import is_placeholder_name, parts  # noqa: E402

CAUSE = Cause(
    id="value-unsafe",
    code="refused",
    failed="checking the value {name}",
    cause="the value holds a quote the engine would read as the end of the string",
    observed="value {value}",
    remedy="quote {name} before passing it",
    test="tests/engine/values.rs::an_unsafe_value_is_refused",
)


class Placeholders(unittest.TestCase):
    def test_a_format_spec_placeholder_is_refused_naming_the_cause_and_the_placeholder(self):
        self.assertEqual(
            replace(CAUSE, observed="value {value:?}").problems(),
            ["cause value-unsafe: `observed` holds the placeholder {value:?}, which the renderer never fills: a placeholder is a lowercase letter, then lowercase letters, digits and '_', between braces, with no format spec; write {value} and have the raising site pass the value already formatted"],
        )
        self.assertEqual(fill("value {value:?}", {"value": "x", "value:?": "y"}), "value {value:?}")

    def test_every_placeholder_the_renderer_will_not_fill_is_refused(self):
        problems = replace(CAUSE, failed="checking {Path} and {deal.title}", remedy="quote {name before passing it").problems()
        self.assertEqual(len(problems), 3, problems)
        self.assertIn("write {path}", problems[0])
        self.assertIn("write {deal_title}", problems[1])
        self.assertIn("`remedy` opens a placeholder at \"{name before passing it\" that no '}' closes", problems[2])
        self.assertIn("`failed` holds a '}' at \"checking a} value\" that no '{' opened", replace(CAUSE, failed="checking a} value").problems()[0])

    def test_a_cause_whose_why_is_only_the_raw_message_is_refused(self):
        problems = replace(CAUSE, cause="{error}").problems()
        self.assertIn("cause value-unsafe: `cause` names {error}, the raw text of the layer below; `cause` is the declaration's own words, so say it in words and move {error} into `observed`", problems)
        self.assertTrue(any(problem.startswith('cause value-unsafe: `cause` is only "{error}", the text it wraps') for problem in problems), problems)
        self.assertEqual(replace(CAUSE, observed="the parser said {problem}").problems(), [])

    def test_the_renderer_reads_a_template_as_every_runtime_does(self):
        self.assertEqual(parts("a {x} {Y} {z"), [("text", "a "), ("placeholder", "x"), ("text", " "), ("malformed", "{Y}"), ("text", " "), ("unclosed", "{z")])
        self.assertEqual(unfilled(["{a} {b}", "{b} {c}"], {"b": "1"}), ["a", "c"])
        for name in PROBES["placeholder"]["valid"]:
            self.assertTrue(is_placeholder_name(name), name)
        for name in PROBES["placeholder"]["invalid"]:
            self.assertFalse(is_placeholder_name(name), name)
        for test in PROBES["test_path"]["valid"] + PROBES["test_path"]["invalid"]:
            refused = any("is not tests/<area>/<file>::<test name>" in problem for problem in replace(CAUSE, test=test).problems())
            self.assertEqual(refused, test in PROBES["test_path"]["invalid"], test)


if __name__ == "__main__":
    unittest.main()
