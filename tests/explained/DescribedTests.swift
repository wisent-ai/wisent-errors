// Real tests of the described decoding every Wisent app reads JSON through:
// `JSONDecoder.decodeDescribed` names the type and the coding path that failed,
// `JSONSerialization.describedObject` says where text stopped being JSON, and a
// value that decodes comes back unchanged.
//
//   swift test --filter DescribedTests

import Foundation
import WisentErrors
import XCTest

final class DescribedTests: XCTestCase {
    private struct Shape: Decodable, Equatable {
        let name: String
        let items: [Int]
    }

    func testAValueThatDecodesComesBackUnchanged() throws {
        let data = Data(#"{"name": "a", "items": [1, 2]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decodeDescribed(Shape.self, from: data), Shape(name: "a", items: [1, 2]))
    }

    func testAMissingKeyNamesTheTypeTheKeyAndWhereItWasMissing() {
        let data = Data(#"{"items": [1, 2]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decodeDescribed(Shape.self, from: data)) { error in
            XCTAssertTrue(error is DescribedDecodingError, String(reflecting: error))
            XCTAssertEqual(error.localizedDescription, "Shape could not be decoded: key \"name\" is missing at the top level")
            XCTAssertEqual(error.explained, error.localizedDescription)
        }
    }

    func testATypeMismatchNamesTheCodingPath() {
        let data = Data(#"{"name": "a", "items": [1, "two"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decodeDescribed(Shape.self, from: data)) { error in
            var reason = "no failure"
            do {
                _ = try JSONDecoder().decode(Shape.self, from: data)
            } catch DecodingError.typeMismatch(_, let context) {
                reason = context.debugDescription
            } catch {
                reason = "another failure: \(error)"
            }
            XCTAssertEqual(error.localizedDescription, "Shape could not be decoded: items.1 is not Int: \(reason)")
        }
    }

    func testTextThatIsNotJSONSaysWhereItStopped() {
        let text = Data("{\"a\": tru}".utf8)
        // Foundation's own reason, asked of it the same way.
        var foundation = "no failure"
        do {
            _ = try JSONSerialization.jsonObject(with: text)
        } catch {
            foundation = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "no reason given"
        }
        XCTAssertThrowsError(try JSONSerialization.describedObject(with: text)) { error in
            XCTAssertTrue(error is DescribedJSONError, String(reflecting: error))
            XCTAssertEqual(error.localizedDescription, foundation)
            XCTAssertTrue(foundation.contains("line 1, column"), foundation)
        }
    }

    func testTextThatIsJSONComesBackAsItsObject() throws {
        let object = try JSONSerialization.describedObject(with: Data(#"{"a": [1]}"#.utf8))
        XCTAssertEqual((object as? [String: [Int]])?["a"], [1])
    }
}
