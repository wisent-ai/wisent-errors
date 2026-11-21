// Support reports through the package's public API (`WisentTelemetry.fileReport`,
// `reports`) and the Report a Problem window's model (`SupportReports`),
// read back from the keys kept on disk: what is refused before anything is
// sent (SupportRefusalTests) and what a real wisent-customer-support named by
// WISENT_SUPPORT_TEST_URL (its /v1/public/reports) answers
// (SupportServiceTests). The agent lists tickets and replies with
// WISENT_SUPPORT_TEST_AGENT_TOKEN, the support-agent token the service holds
// under its own grant (SUPPORT_AGENT_TOKEN, whose role carries the `reply`
// capability) -- the cases tests/telemetry/support.rs holds the Rust client to.
//
//   swift test --filter SupportRefusalTests
//   swift test --filter SupportServiceTests

import Foundation
import XCTest
import WisentErrors
import WisentTelemetryUI

class SupportCase: TelemetryCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // The failure a case queues is sent nowhere rather than to the public collector.
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", Self.nothingListens, 1)
    }

    /// The reports this installation keeps the keys of, from the files on disk.
    func keptOnDisk() throws -> [String] {
        let folder = state.appendingPathComponent("support")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}

final class SupportRefusalTests: SupportCase {
    private let noDescription = "filing a support report: the report has no description; observed: the description is empty; fix: say what you were doing and what happened: in an app's Report a Problem window, or with `wisent-errors-test support report --description \"…\"`"

    func test_a_report_without_a_description_is_refused_before_sending() async throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        do {
            let filed = try await telemetry.fileReport(subject: nil, description: "  ", email: nil, withFailure: false)
            XCTFail("an empty description was filed: \(filed)")
        } catch {
            XCTAssertEqual("\(error)", noDescription)
        }
        let reports = try await telemetry.reports()
        XCTAssertEqual(reports.count, 0)
        XCTAssertEqual(try keptOnDisk(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.appendingPathComponent("installation.json").path), "nothing was made for a report never sent")
    }

    @MainActor
    func test_the_window_says_why_a_report_without_a_description_is_not_sent() async throws {
        let model = SupportReports(telemetry: telemetry(app: "wisent-errors-test-desktop"))
        model.subject = "pairs import fails"
        model.details = "   "
        await model.send()
        XCTAssertEqual(model.failure, noDescription)
        XCTAssertNil(model.filed)
        XCTAssertEqual(model.subject, "pairs import fails", "what the person wrote is kept to correct")
        XCTAssertEqual(try keptOnDisk(), [])
    }

    func test_a_plain_http_support_address_is_refused_by_name() async throws {
        let address = "http://support.example.com/v1/public/reports"
        setenv("WISENT_SUPPORT_URL", address, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        let refusal = "reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds \(address); fix: set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it"
        XCTAssertThrowsError(try telemetry.supportAddress()) { error in XCTAssertEqual("\(error)", refusal) }
        do {
            let filed = try await telemetry.fileReport(subject: nil, description: "something failed", email: nil, withFailure: false)
            XCTFail("a plain-http address was filed to: \(filed)")
        } catch {
            XCTAssertEqual("\(error)", refusal)
        }
        XCTAssertEqual(try keptOnDisk(), [])
        unsetenv("WISENT_SUPPORT_URL")
        let public_ = try telemetry.supportAddress()
        XCTAssertEqual(public_.url.absoluteString, "https://support.wisent.com/v1/public/reports")
        XCTAssertEqual(public_.source, "wisent-errors")
    }

    func test_an_unreachable_support_files_nothing() async throws {
        let address = "http://127.0.0.1:9/v1/public/reports"
        setenv("WISENT_SUPPORT_URL", address, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        var refused = ""
        do {
            let filed = try await telemetry.fileReport(subject: nil, description: "something failed", email: nil, withFailure: false)
            XCTFail("nothing answers, yet it was filed: \(filed)")
        } catch {
            refused = "\(error)"
        }
        let transport = try await ask(address, posting: Data("{}".utf8))
        let why = try XCTUnwrap(transport.failure, "nothing answers \(address)")
        XCTAssertEqual(
            refused,
            "filing a support report at \(address): support could not be reached: \(why); observed: nothing was filed; fix: send the report again once the network or support is back, from an app's Report a Problem window or with `wisent-errors-test support report`")
        let reports = try await telemetry.reports()
        XCTAssertEqual(reports.count, 0)
        XCTAssertEqual(try keptOnDisk(), [])
    }
}

final class SupportServiceTests: SupportCase {
    private func support() throws -> String {
        try required("WISENT_SUPPORT_TEST_URL", "a support service's /v1/public/reports")
    }

    /// A request to the service's own API, as a support agent makes it.
    private func agent(_ path: String) throws -> URLRequest {
        let token = try required(
            "WISENT_SUPPORT_TEST_AGENT_TOKEN",
            "that service's support-agent token (its SUPPORT_AGENT_TOKEN, which carries the reply capability; the service token is refused a reply)")
        var request = URLRequest(url: try XCTUnwrap(URL(string: try origin(try support(), before: "/v1/") + path)))
        request.setValue(token, forHTTPHeaderField: "x-support-token")
        return request
    }

    @MainActor
    func test_the_window_files_a_report_and_shows_its_reply() async throws {
        setenv("WISENT_SUPPORT_URL", try support(), 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure(), causeID: "pairs-unreadable")
        let model = SupportReports(telemetry: telemetry)
        model.subject = "pairs import fails"
        model.details = "the import stops on a file that opens fine"
        await model.send()
        XCTAssertNil(model.failure)
        let kept = try keptOnDisk()
        XCTAssertEqual(kept.count, 1, "one report's key is kept")
        let key = try object(state.appendingPathComponent("support").appendingPathComponent(kept.first ?? ""))
        let id = try XCTUnwrap(key["id"] as? String)
        XCTAssertEqual(kept, ["\(id).json"])
        XCTAssertEqual(key["subject"] as? String, "pairs import fails")
        XCTAssertGreaterThanOrEqual((key["access_key"] as? String)?.count ?? 0, 40)
        XCTAssertEqual(model.filed, "Filed as \(id). Replies appear below.")

        let (listed, _) = try await URLSession.shared.data(for: try agent("/v1/support/tickets"))
        let tickets = try XCTUnwrap(try JSONSerialization.jsonObject(with: listed) as? [[String: Any]])
        let ticket = try XCTUnwrap(tickets.first { $0["public_id"] as? String == id }, "the report is a ticket")
        let report = try XCTUnwrap((ticket["metadata"] as? [String: Any])?["installation_report"] as? [String: Any])
        XCTAssertEqual(report["product"] as? String, "wisent-errors-test")
        XCTAssertEqual(report["app"] as? String, "wisent-errors-test-desktop")
        XCTAssertEqual(report["installation"] as? String, try object(state.appendingPathComponent("installation.json"))["id"] as? String)
        XCTAssertEqual((report["failure"] as? [String: Any])?["cause_id"] as? String, "pairs-unreadable")
        var reply = try agent("/v1/support/tickets/\(try XCTUnwrap(ticket["id"] as? String))/reply")
        reply.httpMethod = "POST"
        reply.setValue("application/json", forHTTPHeaderField: "Content-Type")
        reply.httpBody = Data(#"{"body_text":"Fixed in the next release."}"#.utf8)
        let (answer, response) = try await URLSession.shared.data(for: reply)
        let status = try XCTUnwrap(response as? HTTPURLResponse).statusCode
        XCTAssertTrue(
            (200..<300).contains(status) /* https://www.rfc-editor.org/rfc/rfc9110.html#section-15.3 */,
            "the agent's reply was refused with \(status): \(String(decoding: answer, as: UTF8.self))")

        await model.refresh()
        XCTAssertNil(model.failure)
        let read = try XCTUnwrap(model.reports.first { $0["id"] as? String == id }, "the report reads back")
        XCTAssertEqual(read["status"] as? String, "waiting_on_customer")
        XCTAssertEqual((read["replies"] as? [[String: Any]])?.first?["text"] as? String, "Fixed in the next release.")
    }

    func test_a_report_support_refuses_says_why_and_keeps_nothing() async throws {
        let address = try support()
        setenv("WISENT_SUPPORT_URL", address, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        do {
            let filed = try await telemetry.fileReport(subject: nil, description: "something failed", email: "not an address", withFailure: false)
            XCTFail("support took an email that is not one: \(filed)")
        } catch {
            XCTAssertEqual(
                "\(error)",
                "filing a support report at \(address): support refused HTTP 400: email \"not an address\" is not an email address; observed: nothing was filed; fix: the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `wisent-errors-test support report`")
        }
        let reports = try await telemetry.reports()
        XCTAssertEqual(reports.count, 0)
        XCTAssertEqual(try keptOnDisk(), [])
    }

    func test_an_address_that_is_not_support_is_named() async throws {
        let elsewhere = try origin(try collector(), before: "/api/") + "/robots.txt"
        setenv("WISENT_SUPPORT_URL", elsewhere, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        var refused = ""
        do {
            let filed = try await telemetry.fileReport(subject: nil, description: "something failed", email: nil, withFailure: false)
            XCTFail("the answer is not support's, yet it was filed: \(filed)")
        } catch {
            refused = "\(error)"
        }
        let answer = try await ask(elsewhere, posting: Data("{}".utf8))
        XCTAssertEqual(
            refused,
            "reading support's answer at \(elsewhere): the answer is not a support service's: \(answer.body); observed: HTTP \(answer.status); fix: check that \(elsewhere) is a support service's /v1/public/reports")
        let reports = try await telemetry.reports()
        XCTAssertEqual(reports.count, 0)
        XCTAssertEqual(try keptOnDisk(), [])
    }
}
