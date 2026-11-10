// The Swift telemetry against the real Echo app collector named by
// WISENT_TELEMETRY_TEST_COLLECTOR, each case in its own directory under the
// package's build directory, removed when it ends.

import Foundation
import XCTest
@testable import WisentErrors

final class TelemetryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let build = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build")
            .appendingPathComponent("telemetry-swift-\(UUID().uuidString)")
        root = build
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A failure queued at level errors is sent at once; without a named
        // collector it would go to the public one. Port 9 is the IANA discard
        // port, which nothing on a test machine answers, so a case that does
        // not name the real collector sends nowhere.
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", "http://127.0.0.1:9/api/analytics/mobile/collect", 1)
        unsetenv("DO_NOT_TRACK")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        unsetenv("WISENT_TELEMETRY_COLLECTOR_URL")
    }

    private func telemetry(app: String) -> WisentTelemetry {
        WisentTelemetry(
            product: TelemetryProduct(id: "wisent-errors-test", appID: app, version: "0.0.0"),
            environment: ["WISENT_TELEMETRY_HOME": root.appendingPathComponent("state").path])
    }

    private func failure() -> Failure {
        Failure.orFallback(failurePoint: "wisent-errors-test.pairs.import", code: .notFound, service: "wisent-errors-test")
            .detail("reading \(NSHomeDirectory())/pairs/calm.json: no such file")
    }

    private func collector() throws -> String {
        guard let collector = ProcessInfo.processInfo.environment["WISENT_TELEMETRY_TEST_COLLECTOR"] else {
            throw XCTSkip("blocked, not passed: set WISENT_TELEMETRY_TEST_COLLECTOR to the Echo app collector")
        }
        return collector
    }

    private func settle(_ telemetry: WisentTelemetry, _ report: Failure) {
        let done = expectation(description: "the report settled")
        telemetry.failure(report) { done.fulfill() }
        wait(for: [done], timeout: 60)
    }

    func testNothingIsQueuedBeforeTheUserAnswers() throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        settle(telemetry, failure())
        XCTAssertEqual(telemetry.status()["level"] as? String, "unanswered")
        XCTAssertEqual(try telemetry.queued().count, 0)
    }

    func testTheCommandLinesConsentIsTheAppsConsent() throws {
        let state = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try Data(#"{"level":"errors","answered_at":"2000-01-01T00:00:00Z"}"#.utf8)
            .write(to: state.appendingPathComponent("consent.json"))
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        XCTAssertEqual(try telemetry.level(), .errors)
        settle(telemetry, failure())
        let queued = try telemetry.queued()
        XCTAssertEqual(queued.count, 1)
        let properties = queued[0]["properties"] as? [String: Any]
        let detail = properties?["detail"] as? String ?? ""
        XCTAssertFalse(detail.contains(NSHomeDirectory()), detail)
        XCTAssertTrue(detail.contains("~/pairs/calm.json"), detail)
        XCTAssertEqual(queued[0]["appId"] as? String, "wisent-errors-test-desktop")
    }

    func testAnAppTheCollectorDoesNotDeclareStaysQueuedWithItsRefusal() async throws {
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", try collector(), 1)
        let telemetry = telemetry(app: "wisent-errors-test-undeclared")
        try telemetry.setLevel(.errors)
        settle(telemetry, failure())
        let delivered = await telemetry.flush()
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.remaining, 1)
        let stopped = try XCTUnwrap(delivered.stopped)
        XCTAssertTrue(stopped.contains("HTTP 403"), stopped)
        XCTAssertTrue(stopped.contains("Unknown mobile analytics app"), stopped)
    }

    func testTurningOffDropsWhatWaits() throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, failure())
        try telemetry.setLevel(.off)
        XCTAssertEqual(try telemetry.queued().count, 0)
    }

    func testAPlainHttpCollectorIsRefusedByName() throws {
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", "http://collector.example/api/analytics/mobile/collect", 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        XCTAssertThrowsError(try telemetry.collector()) { error in
            XCTAssertTrue("\(error)".contains("WISENT_TELEMETRY_COLLECTOR_URL holds http://collector.example"), "\(error)")
        }
    }
}
