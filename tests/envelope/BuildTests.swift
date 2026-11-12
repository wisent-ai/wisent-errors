// Real tests of `Failure(failurePoint:code:service:)`'s refusals, each a
// declared cause of `wisent_errors.envelope.build`, and of
// `Failure.orFallback` recording the same cause instead of refusing.
//
//   swift test --filter BuildTests

import XCTest
@testable import WisentErrors

/// The builder accepted what it should have refused; thrown, it fails the test with the envelope it built.
private struct Accepted: Error { let envelope: String }

final class BuildTests: XCTestCase {
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
    }

    func test_an_empty_segment_is_refused() throws {
        let invalid = try refusal("stado..enroll")
        XCTAssertEqual(invalid.cause.id, "failure-point-segment-empty")
        XCTAssertTrue(invalid.message.contains("observed: segments [\"stado\",\"\",\"enroll\"]"), invalid.message)
    }

    func test_a_segment_starting_with_no_letter_is_refused() throws {
        let invalid = try refusal("Brama.dispatch", "brama")
        XCTAssertEqual(invalid.cause.id, "failure-point-segment-start")
        XCTAssertTrue(invalid.message.contains("as 'brama.dispatch'"), invalid.message)
    }

    func test_a_character_outside_the_grammar_is_refused() throws {
        let invalid = try refusal("stado.fleet enroll")
        XCTAssertEqual(invalid.cause.id, "failure-point-character")
        XCTAssertTrue(invalid.message.contains("\"fleet enroll\", holds \" \""), invalid.message)
    }

    func test_a_dangling_separator_is_refused() throws {
        XCTAssertEqual(try refusal("stado.fleet-").cause.id, "failure-point-separator")
        let salvaged = Failure.orFallback(failurePoint: "stado.fleet-", code: .refused, service: "stado")
        XCTAssertEqual(salvaged.context["wisent_errors.failure_point_cause"], "failure-point-separator")
    }

    func test_an_empty_service_is_refused() throws {
        let invalid = try refusal("stado.fleet.enroll", " ")
        XCTAssertEqual(invalid.cause.id, "service-absent")
        XCTAssertTrue(invalid.message.hasPrefix("building the failure envelope at stado.fleet.enroll: the service is empty"), invalid.message)
    }
}
