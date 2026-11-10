// The Swift support client and the Report a Problem window's model against a
// real wisent-customer-support named by WISENT_SUPPORT_TEST_URL (its
// /v1/public/reports), whose agent replies with WISENT_SUPPORT_TEST_TOKEN.

import Foundation
import XCTest
@testable import WisentErrors
@testable import WisentTelemetryUI

final class SupportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build")
            .appendingPathComponent("support-swift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Port 9, the IANA discard port: the failure a case queues is sent
        // nowhere rather than to the public collector.
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", "http://127.0.0.1:9/api/analytics/mobile/collect", 1)
        unsetenv("WISENT_SUPPORT_URL")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        unsetenv("WISENT_SUPPORT_URL")
    }

    private func telemetry() -> WisentTelemetry {
        WisentTelemetry(
            product: TelemetryProduct(id: "wisent-errors-test", appID: "wisent-errors-test-desktop", version: "0.0.0"),
            environment: ["WISENT_TELEMETRY_HOME": root.path])
    }

    private func support() throws -> String {
        guard let url = ProcessInfo.processInfo.environment["WISENT_SUPPORT_TEST_URL"] else {
            throw XCTSkip("blocked, not passed: set WISENT_SUPPORT_TEST_URL to a support service's /v1/public/reports")
        }
        return url
    }

    private func agent(_ path: String) throws -> URLRequest {
        let base = try support()
        let origin = String(base[..<base.range(of: "/v1/")!.lowerBound])
        guard let token = ProcessInfo.processInfo.environment["WISENT_SUPPORT_TEST_TOKEN"] else {
            throw XCTSkip("blocked, not passed: set WISENT_SUPPORT_TEST_TOKEN to that service's support token")
        }
        var request = URLRequest(url: URL(string: origin + path)!)
        request.setValue(token, forHTTPHeaderField: "x-support-token")
        return request
    }

    private func queueFailure(_ telemetry: WisentTelemetry) throws {
        try telemetry.setLevel(.errors)
        let done = expectation(description: "the failure settled")
        telemetry.failure(
            Failure.orFallback(failurePoint: "wisent-errors-test.pairs.import", code: .notFound, service: "wisent-errors-test")
                .detail("reading \(NSHomeDirectory())/pairs/calm.json: no such file"),
            causeID: "pairs-unreadable"
        ) { done.fulfill() }
        wait(for: [done], timeout: 60)
    }

    @MainActor
    func testTheWindowFilesAReportAndShowsItsReply() async throws {
        setenv("WISENT_SUPPORT_URL", try support(), 1)
        let telemetry = telemetry()
        try queueFailure(telemetry)
        let model = SupportReports(telemetry: telemetry)
        model.subject = "pairs import fails"
        model.details = "the import stops on a file that opens fine"
        await model.send()
        XCTAssertNil(model.failure)
        let filed = try XCTUnwrap(model.filed)
        let id = try XCTUnwrap(filed.split(separator: " ").dropFirst(2).first.map { String($0.dropLast()) })

        let (listed, _) = try await URLSession.shared.data(for: try agent("/v1/support/tickets"))
        let tickets = try XCTUnwrap(try JSONSerialization.jsonObject(with: listed) as? [[String: Any]])
        let ticket = try XCTUnwrap(tickets.first { $0["public_id"] as? String == id })
        let report = (ticket["metadata"] as? [String: Any])?["installation_report"] as? [String: Any]
        XCTAssertEqual(report?["app"] as? String, "wisent-errors-test-desktop")
        XCTAssertEqual((report?["failure"] as? [String: Any])?["cause_id"] as? String, "pairs-unreadable")
        var reply = try agent("/v1/support/tickets/\(ticket["id"] as? String ?? "")/reply")
        reply.httpMethod = "POST"
        reply.setValue("application/json", forHTTPHeaderField: "Content-Type")
        reply.httpBody = Data(#"{"body_text":"Fixed in the next release."}"#.utf8)
        _ = try await URLSession.shared.data(for: reply)

        await model.refresh()
        let read = try XCTUnwrap(model.reports.first { $0["id"] as? String == id })
        XCTAssertEqual(read["status"] as? String, "waiting_on_customer")
        XCTAssertEqual((read["replies"] as? [[String: Any]])?.first?["text"] as? String, "Fixed in the next release.")
    }

    func testAReportWithoutADescriptionIsRefusedBeforeSending() async throws {
        do {
            _ = try await telemetry().fileReport(subject: nil, description: "  ", email: nil, withFailure: false)
            XCTFail("an empty description is refused")
        } catch {
            XCTAssertTrue("\(error)".contains("the report has no description"), "\(error)")
        }
    }

    func testAPlainHttpSupportAddressIsRefusedByName() throws {
        setenv("WISENT_SUPPORT_URL", "http://support.example/v1/public/reports", 1)
        XCTAssertThrowsError(try telemetry().supportAddress()) { error in
            XCTAssertTrue("\(error)".contains("WISENT_SUPPORT_URL holds http://support.example"), "\(error)")
        }
        unsetenv("WISENT_SUPPORT_URL")
        XCTAssertEqual(try telemetry().supportAddress().url, WisentTelemetry.publicSupport)
    }

    func testAReportSupportRefusesSaysWhyAndKeepsNothing() async throws {
        setenv("WISENT_SUPPORT_URL", try support(), 1)
        let telemetry = telemetry()
        do {
            _ = try await telemetry.fileReport(subject: nil, description: "something failed", email: "not an address", withFailure: false)
            XCTFail("support refuses the email")
        } catch {
            XCTAssertTrue("\(error)".contains("support refused HTTP 400: email \"not an address\" is not an email address"), "\(error)")
        }
        let reports = try await telemetry.reports()
        XCTAssertEqual(reports.count, 0)
    }

    func testAnUnreachableSupportFilesNothing() async throws {
        setenv("WISENT_SUPPORT_URL", "http://127.0.0.1:9/v1/public/reports", 1)
        let telemetry = telemetry()
        do {
            _ = try await telemetry.fileReport(subject: nil, description: "something failed", email: nil, withFailure: false)
            XCTFail("nothing answers")
        } catch {
            XCTAssertTrue("\(error)".contains("support could not be reached"), "\(error)")
            XCTAssertTrue("\(error)".contains("nothing was filed"), "\(error)")
        }
        let reports = try await telemetry.reports()
        XCTAssertEqual(reports.count, 0)
    }
}
