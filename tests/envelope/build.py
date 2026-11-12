"""Real tests of ``failure()``'s refusals, each a declared cause of
``wisent_errors.envelope.build``, and of ``failure_or_fallback`` recording the
same cause instead of refusing.

    python3 tests/envelope/build.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from wisent_errors import DeclaredError, failure, failure_or_fallback  # noqa: E402


def refused(case, **fields):
    arguments = {"failure_point": "stado.fleet.enroll", "code": "refused", "service": "stado", **fields}
    with case.assertRaises(DeclaredError) as raised:
        failure(**arguments)
    case.assertIsInstance(raised.exception, TypeError)
    case.assertEqual(raised.exception.operation, "wisent_errors.envelope.build")
    return raised.exception


class Build(unittest.TestCase):
    def test_an_empty_point_is_refused(self):
        error = refused(self, failure_point="   ")
        self.assertEqual(error.cause, "failure-point-absent")
        self.assertEqual(
            str(error),
            "building the failure envelope of service stado: the failure point is empty, so the envelope would not say where it broke; observed: failure_point \"   \", nothing once the whitespace around it is trimmed; fix: pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with failure_or_fallback, which records the gap in context instead of refusing",
        )

    def test_an_empty_segment_is_refused(self):
        error = refused(self, failure_point="stado..enroll")
        self.assertEqual(error.cause, "failure-point-segment-empty")
        self.assertIn('observed: segments ["stado","","enroll"]', str(error))

    def test_a_segment_starting_with_no_letter_is_refused(self):
        error = refused(self, failure_point="Brama.dispatch")
        self.assertEqual(error.cause, "failure-point-segment-start")
        self.assertIn("as 'brama.dispatch'", str(error))

    def test_a_character_outside_the_grammar_is_refused(self):
        error = refused(self, failure_point="stado.fleet enroll")
        self.assertEqual(error.cause, "failure-point-character")
        self.assertIn('"fleet enroll", holds " "', str(error))

    def test_a_dangling_separator_is_refused(self):
        self.assertEqual(refused(self, failure_point="stado.fleet-").cause, "failure-point-separator")
        salvaged = failure_or_fallback(failure_point="stado.fleet-", code="refused", service="stado")
        self.assertEqual(salvaged["context"]["wisent_errors.failure_point_cause"], "failure-point-separator")

    def test_an_empty_service_is_refused(self):
        error = refused(self, service=" ")
        self.assertEqual(error.cause, "service-absent")
        self.assertTrue(str(error).startswith("building the failure envelope at stado.fleet.enroll: the service is empty"), str(error))

    def test_a_field_that_is_not_text_is_refused(self):
        error = refused(self, detail=ValueError("connection reset"))
        self.assertEqual(error.cause, "field-not-text")
        self.assertIn("detail is of type ValueError, not text", str(error))
        self.assertIn("observed: detail ValueError: connection reset", str(error))

    def test_an_off_catalogue_code_is_refused(self):
        error = refused(self, code="panic")
        self.assertEqual(error.cause, "code-off-catalogue")
        self.assertIn('the code "panic" is not one of the catalogue\'s', str(error))

    def test_a_blank_detail_is_refused(self):
        error = refused(self, detail="  ")
        self.assertEqual(error.cause, "detail-blank")
        self.assertIn('observed: detail "  "', str(error))


if __name__ == "__main__":
    unittest.main()
