// The Settings section every app shows, through its model: the choice it makes
// is the file the command line reads, an app that declares no product says so,
// and an app no address was given shows Wisent's public collector.

import Foundation
import XCTest
import WisentErrors
@testable import WisentTelemetryUI

@MainActor
final class SettingsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build")
            .appendingPathComponent("telemetry-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        unsetenv("WISENT_TELEMETRY_COLLECTOR_URL")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func telemetry() -> WisentTelemetry {
        WisentTelemetry(
            product: TelemetryProduct(id: "wisent-errors-test", appID: "wisent-errors-test-desktop", version: "0.0.0"),
            environment: ["WISENT_TELEMETRY_HOME": root.path])
    }

    func testTheChoiceIsTheFileTheCommandLineReads() throws {
        let settings = TelemetrySettings(telemetry: telemetry())
        XCTAssertEqual(settings.level, "unanswered")
        settings.set(level: .errors)
        XCTAssertNil(settings.failure)
        XCTAssertEqual(settings.level, "errors")
        let consent = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("consent.json"))) as? [String: Any]
        XCTAssertEqual(consent?["level"] as? String, "errors")
    }

    func testWithoutAnAddressThePublicCollectorIsShown() throws {
        let settings = TelemetrySettings(telemetry: telemetry())
        XCTAssertEqual(settings.status["collector"] as? String, WisentTelemetry.publicCollector.absoluteString)
        XCTAssertEqual(settings.status["collector_source"] as? String, "wisent-errors")
    }

    func testAnAppWithoutAProductHasNothingToChange() {
        let settings = TelemetrySettings(telemetry: nil)
        XCTAssertEqual(settings.level, "unanswered")
        settings.set(level: .errors)
        XCTAssertNil(settings.failure)
        XCTAssertTrue(settings.status.isEmpty)
    }
}
