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
            XCTAssertTrue(
                error.localizedDescription.hasPrefix("Shape could not be decoded: items.1 is not Int"),
                error.localizedDescription)
        }
    }

    func testTextThatIsNotJSONSaysWhereItStopped() {
        XCTAssertThrowsError(try JSONSerialization.describedObject(with: Data("{\"a\": tru}".utf8))) { error in
            XCTAssertTrue(error is DescribedJSONError, String(reflecting: error))
            XCTAssertNotEqual(
                error.localizedDescription, "The data couldn't be read because it isn't in the correct format.")
            XCTAssertTrue(error.localizedDescription.contains("line 1, column"), error.localizedDescription)
        }
    }

    func testTextThatIsJSONComesBackAsItsObject() throws {
        let object = try JSONSerialization.describedObject(with: Data(#"{"a": [1]}"#.utf8))
        XCTAssertEqual((object as? [String: [Int]])?["a"], [1])
    }
}
