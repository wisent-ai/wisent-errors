"""Real tests of ``failure()``: an envelope built whole with every field the
catalogue derives, rendered and chained, raised by ``raise_failure`` and
salvaged by ``failure_or_fallback``; and its refusals, each a declared cause
of ``wisent_errors.envelope.build``, and ``failure_or_fallback`` recording the
same cause instead of refusing.

    python3 tests/envelope/build.py
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from wisent_errors import DeclaredError, FailureError, chain, failure, failure_or_fallback, raise_failure, render  # noqa: E402


def refused(case, **fields):
    arguments = {"failure_point": "stado.fleet.enroll", "code": "refused", "service": "stado", **fields}
    with case.assertRaises(DeclaredError) as raised:
        failure(**arguments)
    case.assertIsInstance(raised.exception, TypeError)
    case.assertEqual(raised.exception.operation, "wisent_errors.envelope.build")
    return raised.exception


class Built(unittest.TestCase):
    def test_an_envelope_is_built_with_the_fields_the_catalogue_derives(self):
        below = failure(failure_point="registry.read", code="not_found", service="registry", detail="no key fleet/example-host")
        built = failure(
            failure_point=" stado.fleet.enroll ",
            code="infra_down",
            service=" stado ",
            impact="  ",
            detail=" connect ECONNREFUSED 127.0.0.1:9 ",
            remedy="start the registry on example-host",
            cause=below,
            context={"host": "example-host"},
        )
        self.assertEqual(
            built,
            {
                "failure_point": "stado.fleet.enroll",
                "error_code": "infra_down",
                "service": "stado",
                "impact": None,
                "severity": "critical",
                "retryable": True,
                "outage": True,
                "detail": "connect ECONNREFUSED 127.0.0.1:9",
                "remedy": "start the registry on example-host",
                "cause": {
                    "failure_point": "registry.read",
                    "error_code": "not_found",
                    "service": "registry",
                    "impact": None,
                    "severity": "warning",
                    "retryable": False,
                    "outage": False,
                    "detail": "no key fleet/example-host",
                    "remedy": None,
                },
                "context": {"host": "example-host"},
            },
        )
        self.assertEqual(
            render(built),
            "infrastructure we depend on is unreachable \u2014 our failure; retry later " + json.dumps(built, separators=(",", ":"), ensure_ascii=False),
        )
        self.assertEqual(chain(built), ["stado.fleet.enroll [infra_down] connect ECONNREFUSED 127.0.0.1:9", "registry.read [not_found] no key fleet/example-host"])
        with self.assertRaises(FailureError) as raised:
            raise_failure(failure_point="stado.fleet.enroll", code="refused", service="stado")
        self.assertEqual(str(raised.exception), "stado.fleet.enroll: an explicit policy refused this command")

    def test_a_malformed_envelope_on_an_error_path_is_salvaged_with_its_gaps_recorded(self):
        self.assertEqual(
            failure_or_fallback(code="panic", detail="disk full"),
            {
                "failure_point": "unknown",
                "error_code": "unknown",
                "service": "unknown",
                "impact": None,
                "severity": "error",
                "retryable": False,
                "outage": False,
                "detail": "disk full",
                "remedy": None,
                "context": {
                    "wisent_errors.failure_point": "absent",
                    "wisent_errors.error_code": "off-catalogue: panic",
                    "wisent_errors.service": "absent",
                },
            },
        )


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
        self.assertEqual(
            str(error),
            "building the failure envelope of service stado: segment 2 of the failure point \"stado..enroll\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"stado\",\"\",\"enroll\"]; fix: drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with failure_or_fallback",
        )

    def test_a_segment_starting_with_no_letter_is_refused(self):
        error = refused(self, failure_point="Brama.dispatch")
        self.assertEqual(error.cause, "failure-point-segment-start")
        self.assertEqual(
            str(error),
            "building the failure envelope of service stado: segment 1 of the failure point \"Brama.dispatch\", \"Brama\", starts with \"B\", and a segment starts with a lowercase letter; observed: segments [\"Brama\",\"dispatch\"]; fix: start the segment with a lowercase letter, as 'brama.dispatch'; on an error path build it with failure_or_fallback",
        )

    def test_a_character_outside_the_grammar_is_refused(self):
        error = refused(self, failure_point="stado.fleet enroll")
        self.assertEqual(error.cause, "failure-point-character")
        self.assertEqual(
            str(error),
            "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet enroll\", \"fleet enroll\", holds \" \", which is not a lowercase letter, a digit, '-' or '_'; observed: segments [\"stado\",\"fleet enroll\"]; fix: write the point in lowercase letters, digits and single '-' or '_', as 'stado.fleet-enroll'; on an error path build it with failure_or_fallback",
        )

    def test_a_dangling_separator_is_refused(self):
        error = refused(self, failure_point="stado.fleet-")
        self.assertEqual(error.cause, "failure-point-separator")
        self.assertEqual(
            str(error),
            "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet-\", \"fleet-\", ends with a separator or holds two together, and '-' and '_' only join two words; observed: segments [\"stado\",\"fleet-\"]; fix: keep one '-' or '_' between two words of a segment, as 'stado.fleet'; on an error path build it with failure_or_fallback",
        )
        salvaged = failure_or_fallback(failure_point="stado.fleet-", code="refused", service="stado")
        self.assertEqual(salvaged["context"]["wisent_errors.failure_point_cause"], "failure-point-separator")

    def test_an_empty_service_is_refused(self):
        error = refused(self, service=" ")
        self.assertEqual(error.cause, "service-absent")
        self.assertEqual(
            str(error),
            "building the failure envelope at stado.fleet.enroll: the service is empty, so the envelope would not say which component failed; observed: service \" \", nothing once the whitespace around it is trimmed; fix: pass the name of the component raising it, as in 'stado'; on an error path build it with failure_or_fallback, which records the gap in context",
        )

    def test_a_field_that_is_not_text_is_refused(self):
        reset = ValueError("connection reset")
        error = refused(self, detail=reset)
        self.assertEqual(error.cause, "field-not-text")
        self.assertEqual(
            str(error),
            f"building the failure envelope at stado.fleet.enroll: detail is of type {type(reset).__name__}, not text, so the envelope could not carry it as written; observed: detail {type(reset).__name__}: {reset}; fix: pass detail as a string; an error from the layer below goes in as its message, as in str(error)",
        )

    def test_an_off_catalogue_code_is_refused(self):
        error = refused(self, code="panic")
        self.assertEqual(error.cause, "code-off-catalogue")
        self.assertEqual(
            str(error),
            "building the failure envelope at stado.fleet.enroll: the code \"panic\" is not one of the catalogue's, so nothing could derive its severity, retryability or exit status; observed: the catalogue's codes are config, auth, not_found, rate_limit, timeout, infra_down, refused, unknown; fix: pass one of the catalogue's codes; on a wire boundary read it with code_or_fallback, which keeps an unknown code as the fallback",
        )

    def test_a_blank_detail_is_refused(self):
        error = refused(self, detail="  ")
        self.assertEqual(error.cause, "detail-blank")
        self.assertEqual(
            str(error),
            "building the failure envelope at stado.fleet.enroll: a detail was given but holds only whitespace, so it would read as a reason while saying none; observed: detail \"  \"; fix: pass the reason the layer below gave, or leave detail out, which writes null",
        )


if __name__ == "__main__":
    unittest.main()
