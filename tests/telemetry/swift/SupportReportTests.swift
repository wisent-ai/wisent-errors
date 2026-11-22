// `wisent-errors-swift support report` and `support status`, the package's
// command line filing a product's support report the way its app's Help →
// Report a Problem window files it (`WisentTelemetry.fileReport`,
// `reports`, docs/support.md), run as a process and read back from the keys
// kept on disk: what is refused before anything is filed
// (SupportRefusalTests), and what a real wisent-customer-support answers
// (SupportServiceTests): a report filed with the newest queued failure, an
// email it refuses, an address that is not support, and the reply its agent
// writes read back -- the cases tests/telemetry/support.rs holds the Rust
// client to.
//
//   swift test --filter SupportRefusalTests
//   swift test --filter SupportServiceTests
//
// Rule 4: each case runs the built wisent-errors-swift (CommandCase.swift).
// Nothing stands in for support: SupportRefusalTests files to the discard
// port on loopback, where nothing listens, so the refusal it reads is the
// real transport's; SupportServiceTests files to the real service
// WISENT_SUPPORT_TEST_URL names (its /v1/public/reports), whose agent lists
// and replies with WISENT_SUPPORT_TEST_AGENT_TOKEN (the service's
// SUPPORT_AGENT_TOKEN, carrying the reply capability, handed through the
// environment, never argv), and fails as blocked naming the variable when it
// is not set, never passes.
// Rule 9: the command cannot be built here, so no sentence was probed: each
// expected refusal is the cause's template in catalogue/failures/telemetry.json
// or swift-cli.json rendered whole with the values the case observes; where
// a sentence quotes the transport or support, the case asks the same
// address the same way in this process and compares the whole sentence.

#if os(macOS)
import Foundation
import XCTest

class SupportCase: TelemetryCase {
    var support: URL { state.appendingPathComponent("support") }

    /// The reports this installation keeps the keys of, from the files on disk.
    func keptOnDisk() throws -> [String] {
        guard FileManager.default.fileExists(atPath: support.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: support.path).sorted()
    }

    /// `support report` of a description, with `more` options.
    func report(_ description: String, _ more: [String] = []) -> [String] {
        ["support", "report"] + product() + ["--description", description] + more
    }

    /// A refusal of `wisent-errors.support.exchange`.
    func exchange(_ cause: String, status: Int32, _ sentence: String, fix: String) -> Ran {
        telemetryRefusal("wisent-errors.support.exchange", cause, status: status, sentence, fix: fix)
    }
}

final class SupportRefusalTests: SupportCase {
    func test_support_report_refuses_what_cannot_be_filed_and_files_nothing() throws {
        let address = "http://127.0.0.1:9/v1/public/reports"
        let unreachable = telemetry(["WISENT_SUPPORT_URL": address])

        // No description, or one that is only whitespace.
        XCTAssertEqual(try run(["support", "report"] + product(), environment: unreachable), usage(
            "option-required",
            "reading the options of `wisent-errors-swift support report`: it needs --description, and --description was not given; observed: options given: --app, --app-version, --product",
            fix: "add --description, as in `--description \"the pairs import stops on a file that opens fine\"`"))
        XCTAssertEqual(try run(report("  "), environment: unreachable), telemetryRefusal(
            "wisent-errors.support.report", "support-description-empty", status: 2,
            "filing a support report: the report has no description; observed: the description is empty",
            fix: "say what you were doing and what happened: in an app's Report a Problem window, or with `wisent-errors-test support report --description \"…\"`"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "nothing was made for a report never sent")

        // A plain-http address, refused by name before anything is sent.
        let plain = "http://support.example.com/v1/public/reports"
        XCTAssertEqual(try run(report("something failed"), environment: telemetry(["WISENT_SUPPORT_URL": plain])), exchange(
            "support-address-invalid", status: 1,
            "reading the support address from WISENT_SUPPORT_URL: a support address must be https://, or http:// on a loopback host; observed: WISENT_SUPPORT_URL holds \(plain)",
            fix: "set WISENT_SUPPORT_URL to the https:// address of a support service's /v1/public/reports, or unset it"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "nothing was made for a report never sent")

        // Nothing listening: the transport's own failure, and nothing filed.
        let why = try XCTUnwrap(try ask(address, posting: Data("{}".utf8)).failure, "nothing answers \(address)")
        XCTAssertEqual(try run(report("something failed"), environment: unreachable), exchange(
            "support-unreachable", status: 69,
            "filing a support report at \(address): support could not be reached: \(why); observed: nothing was filed",
            fix: "send the report again once the network or support is back, from an app's Report a Problem window or with `wisent-errors-test support report`"))
        XCTAssertEqual(try keptOnDisk(), [], "no key is kept for a report never filed")
        XCTAssertEqual(try tree(state), ["installation.json"], "only the installation id the report carries is kept")
    }

    func test_support_status_reads_the_reports_kept_or_names_a_key_it_cannot() throws {
        let status = ["support", "status"] + product()

        // No report filed: an empty list, and nothing made.
        let none = try run(status, environment: telemetry())
        XCTAssertEqual(none.status, 0, "\(none)")
        XCTAssertEqual(none.stderr, "")
        XCTAssertEqual(try printed(none) as? NSArray, [] as NSArray)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path))

        // A key file telemetry did not write.
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let stray = support.appendingPathComponent("stray.json")
        try Data("[]".utf8).write(to: stray)
        XCTAssertEqual(try run(status, environment: telemetry()), telemetryRefusal(
            "wisent-errors.telemetry.store", "file-unreadable", status: 1,
            "reading a support report's key from \(stray.path): the file is not what telemetry wrote: it is not a JSON object; observed: the file holds 2 bytes",
            fix: "answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove \(stray.path)"))
        XCTAssertEqual(try text(stray), "[]", "the damaged key is left as it was")
    }
}

final class SupportServiceTests: SupportCase {
    private func service() throws -> String {
        try required("WISENT_SUPPORT_TEST_URL", "a support service's /v1/public/reports")
    }

    /// A request to the service's own API, as a support agent makes it.
    private func agent(_ path: String) throws -> URLRequest {
        let token = try required(
            "WISENT_SUPPORT_TEST_AGENT_TOKEN",
            "that service's support-agent token (its SUPPORT_AGENT_TOKEN, which carries the reply capability; the service token is refused a reply)")
        var request = URLRequest(url: try XCTUnwrap(URL(string: try origin(try service(), before: "/v1/") + path)))
        request.setValue(token, forHTTPHeaderField: "x-support-token")
        return request
    }

    /// What the service answers `request`: its status and body.
    private func fetch(_ request: URLRequest) throws -> (status: Int, body: Data) {
        // fallback: a request is always made to a URL; "support" names one that has none.
        let done = expectation(description: "\(request.url?.absoluteString ?? "support") answered")
        var answered: (Int, Data) = (0, Data())
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            XCTAssertNil(error, "the service answered")
            // fallback: a request the transport failed has no status or body; the assertion above says why.
            answered = ((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data())
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 120)
        return answered
    }

    /// The one report filed: what the command printed, checked against the key kept on disk.
    private func filed(_ ran: Ran, _ address: String) throws -> (id: String, key: [String: Any]) {
        XCTAssertEqual(ran.status, 0, "\(ran)")
        let answer = try XCTUnwrap(try printed(ran) as? [String: Any], ran.stdout)
        let id = try XCTUnwrap(answer["id"] as? String, ran.stdout)
        let kept = support.appendingPathComponent("\(id).json")
        XCTAssertEqual(answer["address"] as? String, address)
        XCTAssertEqual(answer["kept"] as? String, kept.path)
        XCTAssertNil(answer["access_key"], "the key is kept on disk, never printed")
        let key = try object(kept)
        XCTAssertEqual(key["id"] as? String, id)
        // fallback: a key that is not text counts as none, which the assertion refuses.
        XCTAssertGreaterThanOrEqual((key["access_key"] as? String)?.count ?? 0, 40)
        return (id, key)
    }

    func test_support_report_files_to_the_real_service_or_says_what_it_refused() throws {
        let address = try service()
        let reaching = telemetry(["WISENT_SUPPORT_URL": address, "WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens])

        // Filed, with the newest failure waiting in the queue.
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: reaching).status, 0)
        XCTAssertEqual(try run(failure("wisent-errors-test-desktop", ["--cause-id", "pairs-unreadable"]), environment: reaching).status, 0)
        let ran = try run(report("the import stops on a file that opens fine", ["--subject", "pairs import fails", "--with-failure"]), environment: reaching)
        let (id, key) = try filed(ran, address)
        XCTAssertEqual((try printed(ran) as? [String: Any])?["with_failure"] as? Bool, true)
        XCTAssertEqual(key["subject"] as? String, "pairs import fails")
        XCTAssertEqual(try keptOnDisk(), ["\(id).json"])
        let (listed, listing) = try fetch(try agent("/v1/support/tickets"))
        XCTAssertEqual(listed, 200, String(decoding: listing, as: UTF8.self))
        let tickets = try XCTUnwrap(try JSONSerialization.jsonObject(with: listing) as? [[String: Any]])
        let ticket = try XCTUnwrap(tickets.first { $0["public_id"] as? String == id }, "the report is a ticket")
        let sent = try XCTUnwrap((ticket["metadata"] as? [String: Any])?["installation_report"] as? [String: Any])
        XCTAssertEqual(sent["product"] as? String, "wisent-errors-test")
        XCTAssertEqual(sent["app"] as? String, "wisent-errors-test-desktop")
        XCTAssertEqual(sent["installation"] as? String, try object(state.appendingPathComponent("installation.json"))["id"] as? String)
        XCTAssertEqual((sent["failure"] as? [String: Any])?["cause_id"] as? String, "pairs-unreadable")

        // An email support refuses: its own reason, and nothing more kept.
        XCTAssertEqual(try run(report("something failed", ["--email", "not an address"]), environment: reaching), exchange(
            "support-refused", status: 1,
            "filing a support report at \(address): support refused HTTP 400: email \"not an address\" is not an email address; observed: nothing was filed",
            fix: "the answer is support's own reason: correct what it names and send the report again, from an app's Report a Problem window or with `wisent-errors-test support report`"))
        XCTAssertEqual(try keptOnDisk(), ["\(id).json"])

        // An address that is not support: its answer named, nothing kept.
        let robots = try origin(address, before: "/v1/") + "/robots.txt"
        let notSupport = try ask(robots, posting: Data("{}".utf8))
        XCTAssertEqual(try run(report("something failed"), environment: telemetry(["WISENT_SUPPORT_URL": robots])), exchange(
            "support-answer-unreadable", status: 69,
            "reading support's answer at \(robots): the answer is not a support service's: \(notSupport.body); observed: HTTP \(notSupport.status)",
            fix: "check that \(robots) is a support service's /v1/public/reports"))
        XCTAssertEqual(try keptOnDisk(), ["\(id).json"])
    }

    func test_support_status_reads_the_agents_reply_to_a_filed_report() throws {
        let address = try service()
        let reaching = telemetry(["WISENT_SUPPORT_URL": address])
        let (id, _) = try filed(try run(report("the import stops on a file that opens fine", ["--subject", "pairs import fails"]), environment: reaching), address)

        let (listed, listing) = try fetch(try agent("/v1/support/tickets"))
        XCTAssertEqual(listed, 200, String(decoding: listing, as: UTF8.self))
        let tickets = try XCTUnwrap(try JSONSerialization.jsonObject(with: listing) as? [[String: Any]])
        let ticket = try XCTUnwrap(tickets.first { $0["public_id"] as? String == id }, "the report is a ticket")
        var reply = try agent("/v1/support/tickets/\(try XCTUnwrap(ticket["id"] as? String))/reply")
        reply.httpMethod = "POST"
        reply.setValue("application/json", forHTTPHeaderField: "Content-Type")
        reply.httpBody = Data(#"{"body_text":"Fixed in the next release."}"#.utf8)
        let (replied, answer) = try fetch(reply)
        XCTAssertTrue(
            (200..<300).contains(replied) /* https://www.rfc-editor.org/rfc/rfc9110.html#section-15.3 */,
            "the agent's reply was refused with \(replied): \(String(decoding: answer, as: UTF8.self))")

        let status = try run(["support", "status"] + product(), environment: reaching)
        XCTAssertEqual(status.status, 0, "\(status)")
        XCTAssertEqual(status.stderr, "")
        let reports = try XCTUnwrap(try printed(status) as? [[String: Any]], status.stdout)
        XCTAssertEqual(reports.count, 1, status.stdout)
        let read = try XCTUnwrap(reports.first)
        XCTAssertEqual(read["id"] as? String, id)
        XCTAssertEqual(read["status"] as? String, "waiting_on_customer")
        XCTAssertEqual((read["replies"] as? [[String: Any]])?.first?["text"] as? String, "Fixed in the next release.")
        XCTAssertEqual(try keptOnDisk(), ["\(id).json"], "reading the reply kept nothing more")
    }
}
#endif
