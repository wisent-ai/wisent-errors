// The Settings section every app shows, through its public model
// (`TelemetrySettings` of WisentTelemetryUI): the choice it makes is the file
// the command line reads, an app no address was given shows Wisent's public
// collector, and an app that declares no product has nothing to change.
//
//   swift test --filter SettingsWindowTests

import Foundation
import XCTest
import WisentErrors
import WisentTelemetryUI

final class SettingsWindowTests: TelemetryCase {
    @MainActor
    func test_the_choice_is_the_file_the_command_line_reads() throws {
        let settings = TelemetrySettings(telemetry: telemetry(app: "wisent-errors-test-desktop"))
        XCTAssertEqual(settings.level, "unanswered")
        settings.set(level: .errors)
        XCTAssertNil(settings.failure)
        XCTAssertEqual(settings.level, "errors")
        XCTAssertEqual(try object(state.appendingPathComponent("consent.json"))["level"] as? String, "errors")
        // What the command line reads from the same directory.
        XCTAssertEqual(try telemetry(app: "wisent-errors-test-cli").level(), .errors)
    }

    @MainActor
    func test_without_an_address_the_public_collector_is_shown() {
        let settings = TelemetrySettings(telemetry: telemetry(app: "wisent-errors-test-desktop"))
        XCTAssertEqual(settings.status["collector"] as? String, "https://telemetry.wisent.com/api/analytics/mobile/collect")
        XCTAssertEqual(settings.status["collector_source"] as? String, "wisent-errors")
    }

    @MainActor
    func test_an_app_without_a_product_has_nothing_to_change() throws {
        let settings = TelemetrySettings(telemetry: nil)
        XCTAssertEqual(settings.level, "unanswered")
        settings.set(level: .errors)
        XCTAssertNil(settings.failure)
        XCTAssertTrue(settings.status.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], "nothing was written")
    }
}
