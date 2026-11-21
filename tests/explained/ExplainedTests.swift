// Real tests of `Error.explained`, the sentence every Wisent app shows a person
// for a failure instead of `localizedDescription`: a declared description as
// declared, a decoding failure with the coding path it stopped at, an encoding
// failure with the value, path and reason the encoder gave, a Cocoa error with
// its domain and code, any other error as its type and value, and the
// underlying errors after it, read until the chain ends or repeats.
//
//   swift test --filter ExplainedTests

import Foundation
import XCTest
import WisentErrors

final class ExplainedTests: XCTestCase {
    private struct Declared: LocalizedError {
        var errorDescription: String? { "the report could not be written" }
    }

    private struct Undeclared: Error {
        let code: Int
    }

    private struct Shape: Decodable {
        let name: String
        let items: [Int]
    }

    func testADeclaredDescriptionIsSaidAsDeclared() {
        XCTAssertEqual(Declared().explained, "the report could not be written")
    }

    func testAnUndeclaredErrorIsSaidAsItsTypeAndValue() {
        let said = Undeclared(code: 7).explained
        XCTAssertEqual(said, String(reflecting: Undeclared(code: 7)))
        XCTAssertTrue(said.hasSuffix("Undeclared(code: 7)"), said)
    }

    /// The decoder's or encoder's own words for `attempt`'s failure, read from its context.
    private func debugDescription(_ attempt: () throws -> Void) -> String {
        do {
            try attempt()
        } catch DecodingError.typeMismatch(_, let context) {
            return context.debugDescription
        } catch EncodingError.invalidValue(_, let context) {
            return context.debugDescription
        } catch {
            return "another failure: \(error)"
        }
        return "no failure"
    }

    func testAMissingKeyNamesTheKeyAndWhereItWasMissing() throws {
        let data = Data(#"{"items": [1, 2]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Shape.self, from: data)) { error in
            XCTAssertEqual(error.explained, "key \"name\" is missing at the top level")
        }
    }

    func testATypeMismatchNamesTheCodingPath() throws {
        let data = Data(#"{"name": "a", "items": [1, "two"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Shape.self, from: data)) { error in
            let reason = debugDescription { _ = try JSONDecoder().decode(Shape.self, from: data) }
            XCTAssertEqual(error.explained, "items.1 is not Int: \(reason)")
        }
    }

    func testAnEncodingFailureNamesTheValueThePathAndTheEncodersReason() throws {
        let value = ["prices": [1.5, Double.infinity]]
        XCTAssertThrowsError(try JSONEncoder().encode(value)) { error in
            let reason = debugDescription { _ = try JSONEncoder().encode(value) }
            XCTAssertEqual(error.explained, "Double inf cannot be encoded at prices.1: \(reason)")
        }
    }

    func testACocoaErrorSaysItsDomainCodeAndEveryUnderlyingError() {
        let cause = NSError(domain: NSPOSIXErrorDomain, code: 13, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "The file could not be saved.", NSUnderlyingErrorKey: cause]
        )
        XCTAssertEqual(
            error.explained,
            "The file could not be saved. (NSCocoaErrorDomain 513): Permission denied (NSPOSIXErrorDomain 13)"
        )
    }

    func testAChainThatComesBackToAnErrorAlreadySaidEnds() {
        let inner = NSError(domain: "Example", code: 1, userInfo: [NSLocalizedDescriptionKey: "inner"])
        let outer = NSError(domain: "Example", code: 1, userInfo: [NSLocalizedDescriptionKey: "inner", NSUnderlyingErrorKey: inner])
        XCTAssertEqual(outer.explained, "inner (Example 1)")
    }
}
