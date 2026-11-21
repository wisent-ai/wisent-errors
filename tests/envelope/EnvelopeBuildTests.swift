// Real tests of `Failure(failurePoint:code:service:)`'s refusals through the
// package's public API, each a declared cause of
// `wisent_errors.envelope.build`: the whole sentence the refusal says, the
// cause it names, and that `Failure.orFallback` records the same gap in the
// envelope's context instead of refusing -- the cases tests/envelope/build.rs
// holds the Rust crate to.
//
//   swift test --filter EnvelopeBuildTests

import XCTest
import WisentErrors

/// The builder accepted what it should have refused; thrown, it fails the test with the envelope it built.
private struct Accepted: Error, CustomStringConvertible {
    let envelope: String
    var description: String { "the builder accepted \(envelope)" }
}

final class EnvelopeBuildTests: XCTestCase {
    private func refusal(_ point: String, _ service: String = "stado") throws -> Invalid {
        do {
            let built = try Failure(failurePoint: point, code: .refused, service: service)
            throw Accepted(envelope: built.toJSON())
        } catch let invalid as Invalid {
            return invalid
        }
    }

    func test_an_empty_point_is_refused() throws {
        let invalid = try refusal("   ")
        XCTAssertEqual(invalid.cause.id, "failure-point-absent")
        XCTAssertEqual(
            invalid.message,
            "building the failure envelope of service stado: the failure point is empty, so the envelope would not say where it broke; observed: failure_point \"   \", nothing once the whitespace around it is trimmed; fix: pass the dotted lowercase path of the step that failed, as in 'stado.fleet.enroll'; on an error path build it with Failure.orFallback, which records the gap in context instead of refusing"
        )
        let salvaged = Failure.orFallback(failurePoint: "   ", code: .refused, service: "stado")
        XCTAssertEqual(
            salvaged.toJSON(),
            #"{"failure_point":"unknown","error_code":"refused","service":"stado","impact":null,"severity":"warning","retryable":false,"outage":false,"detail":null,"remedy":null,"context":{"wisent_errors.failure_point":"absent"}}"#
        )
    }

    func test_an_empty_segment_is_refused() throws {
        let invalid = try refusal("stado..enroll")
        XCTAssertEqual(invalid.cause.id, "failure-point-segment-empty")
        XCTAssertEqual(
            invalid.message,
            "building the failure envelope of service stado: segment 2 of the failure point \"stado..enroll\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"stado\",\"\",\"enroll\"]; fix: drop the extra dot, so every segment between dots holds a name, as in 'stado.fleet.enroll'; on an error path build it with Failure.orFallback"
        )
        XCTAssertEqual(
            Failure.orFallback(failurePoint: "stado..enroll", code: .refused, service: "stado").context,
            ["wisent_errors.failure_point": "malformed", "wisent_errors.failure_point_cause": "failure-point-segment-empty"]
        )
    }

    func test_a_segment_starting_with_no_letter_is_refused() throws {
        let invalid = try refusal("Brama.dispatch", "brama")
        XCTAssertEqual(invalid.cause.id, "failure-point-segment-start")
        XCTAssertEqual(
            invalid.message,
            "building the failure envelope of service brama: segment 1 of the failure point \"Brama.dispatch\", \"Brama\", starts with \"B\", and a segment starts with a lowercase letter; observed: segments [\"Brama\",\"dispatch\"]; fix: start the segment with a lowercase letter, as 'brama.dispatch'; on an error path build it with Failure.orFallback"
        )
        XCTAssertEqual(
            Failure.orFallback(failurePoint: "Brama.dispatch", code: .refused, service: "brama").context,
            ["wisent_errors.failure_point": "malformed", "wisent_errors.failure_point_cause": "failure-point-segment-start"]
        )
    }

    func test_a_character_outside_the_grammar_is_refused() throws {
        let invalid = try refusal("stado.fleet enroll")
        XCTAssertEqual(invalid.cause.id, "failure-point-character")
        XCTAssertEqual(
            invalid.message,
            "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet enroll\", \"fleet enroll\", holds \" \", which is not a lowercase letter, a digit, '-' or '_'; observed: segments [\"stado\",\"fleet enroll\"]; fix: write the point in lowercase letters, digits and single '-' or '_', as 'stado.fleet-enroll'; on an error path build it with Failure.orFallback"
        )
        XCTAssertEqual(
            Failure.orFallback(failurePoint: "stado.fleet enroll", code: .refused, service: "stado").context,
            ["wisent_errors.failure_point": "malformed", "wisent_errors.failure_point_cause": "failure-point-character"]
        )
    }

    func test_a_dangling_separator_is_refused() throws {
        let invalid = try refusal("stado.fleet-")
        XCTAssertEqual(invalid.cause.id, "failure-point-separator")
        XCTAssertEqual(
            invalid.message,
            "building the failure envelope of service stado: segment 2 of the failure point \"stado.fleet-\", \"fleet-\", ends with a separator or holds two together, and '-' and '_' only join two words; observed: segments [\"stado\",\"fleet-\"]; fix: keep one '-' or '_' between two words of a segment, as 'stado.fleet'; on an error path build it with Failure.orFallback"
        )
        let salvaged = Failure.orFallback(failurePoint: "stado.fleet-", code: .refused, service: "stado")
        XCTAssertEqual(salvaged.failurePoint, "stado.fleet-", "the malformed point is kept verbatim")
        XCTAssertEqual(
            salvaged.context,
            ["wisent_errors.failure_point": "malformed", "wisent_errors.failure_point_cause": "failure-point-separator"]
        )
    }

    func test_an_empty_service_is_refused() throws {
        let invalid = try refusal("stado.fleet.enroll", " ")
        XCTAssertEqual(invalid.cause.id, "service-absent")
        XCTAssertEqual(
            invalid.message,
            "building the failure envelope at stado.fleet.enroll: the service is empty, so the envelope would not say which component failed; observed: service \" \", nothing once the whitespace around it is trimmed; fix: pass the name of the component raising it, as in 'stado'; on an error path build it with Failure.orFallback, which records the gap in context"
        )
        let salvaged = Failure.orFallback(failurePoint: "stado.fleet.enroll", code: .refused, service: " ")
        XCTAssertEqual(salvaged.service, "unknown")
        XCTAssertEqual(salvaged.context, ["wisent_errors.service": "absent"])
    }
}
