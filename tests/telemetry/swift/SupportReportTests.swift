// `wisent-errors-swift support report` and `support status`, the package's
// command line filing a product's support report the way its app's Help →
// Report a Problem window files it (`WisentTelemetry.fileReport`,
// `reports`, docs/support.md), run as a process and read back from the keys
// kept on disk: what is refused before anything is filed, a damaged key,
// and an answer that is not support's said on one line
// (SupportRefusalTests), and what a real wisent-customer-support answers
// (SupportServiceTests): a report filed with the newest queued failure, an
// email it refuses, and the reply its agent writes read back -- the cases
// tests/telemetry/support.rs holds the Rust client to.
//
//   swift test --filter SupportRefusalTests
//   swift test --filter SupportServiceTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the product's own
// binary, wisent-errors-swift -- the executable product Package.swift
// declares, the one a release ships, which `swift test` links beside the
// test bundle (CommandCase.executable) -- as a child process:
// `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195). Nothing stands in for
// support: SupportRefusalTests defends what is refused before anything is
// filed, and files to a loopback port where no process listens (RFC 863's
// discard port), so the refusal it reads is the real transport's failing in
// the child; its one-line case posts to the real public support host's
// /robots.txt (https://support.wisent.com), which files nothing and answers
// a page of text; no server, stub or canned answer exists in either class.
// SupportServiceTests files to the real wisent-customer-support service
// WISENT_SUPPORT_TEST_URL names (its /v1/public/reports), whose agent lists
// and replies with WISENT_SUPPORT_TEST_AGENT_TOKEN (the service's
// SUPPORT_AGENT_TOKEN, carrying the reply capability, handed through the
// environment, never argv), and reads the ticket back from the service; it
// fails as blocked naming the variable when it is not set, never passes.
// Rule 9: every sentence, file and exit status of SupportRefusalTests was
// copied from live runs of wisent-errors-swift built from this tree (`swift
// build --product wisent-errors-swift`, 2026-11-21): each step run by hand
// under `env -i` given only HOME, CFFIXED_USER_HOME, TMPDIR, XDG_* and the
// case's WISENT_TELEMETRY_HOME and WISENT_SUPPORT_URL inside
// target/probe-swift/support*, the stray key written as here, the locked
// key chmod 000 and restored, and the telemetry home listed after each; the
// transport's words are the ones those runs printed
// (TelemetryCase.unconnected). The public host's robots.txt answered HTTP
// 404 with "The page could not be found\n\nNOT_FOUND\n\n<a request id>\n",
// said live as one JSON string, which carries an id of its own per request,
// so that part is read back, not pinned. SupportServiceTests was probed
// live on 2026-11-22 against this host's wisent-customer-support (the
// address its vault item wisent-customer-support-tokens names, its agent
// token from the same item), the steps run by hand as above: `telemetry
// set`, `telemetry failure`, then `support report --email "not an address"`
// said exactly the support-refused sentence asserted below, exit 1, nothing
// kept. Filing was refused by that deployment with "support refused HTTP
// 400: the request carries no x-forwarded-for header, which this deployment
// reads the reporter's address from": it is started to sit behind a front
// that is not there, a defect of the deployment, so the filed report and
// the agent's reply fail there until the service is started as its catalog
// record declares; without WISENT_SUPPORT_TEST_URL and the agent token the
// class fails as blocked naming them, never passes.

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
        XCTAssertEqual(try run(report("something failed"), environment: unreachable), exchange(
            "support-unreachable", status: 69,
            "filing a support report at \(address): support could not be reached: \(Self.unconnected); observed: nothing was filed",
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

        // A key file filing a report did not write: its fix names what keeps a key again.
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let stray = support.appendingPathComponent("stray.json")
        try Data("[]".utf8).write(to: stray)
        XCTAssertEqual(try run(status, environment: telemetry()), telemetryRefusal(
            "wisent-errors.telemetry.store", "support-key-unreadable", status: 1,
            "reading a support report's key from \(stray.path): the file is not the key filing a report kept: it is not a JSON object; observed: the file holds 2 bytes",
            fix: "remove \(stray.path) and file the report again, with `wisent-errors-test support report` or from an app's Report a Problem window, which keeps the new report's key; the replies to the report that file held the key of cannot be read without that key"))
        XCTAssertEqual(try text(stray), "[]", "the damaged key is left as it was")
        XCTAssertEqual(try tree(state), ["support", "support/stray.json"], "reading the keys kept nothing more")
        try FileManager.default.removeItem(at: stray)

        // A key file the system will not read: no permission for anyone. Its fix names chmod, and that nothing writes the key again.
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        let locked = support.appendingPathComponent("locked.json")
        let key = Data(#"{"id":"r-1"}"#.utf8)
        try key.write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let refused = try run(status, environment: telemetry())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked.path)
        XCTAssertEqual(refused, telemetryRefusal(
            "wisent-errors.telemetry.store", "support-key-read-refused", status: 1,
            "reading a support report's key from \(locked.path): the operating system refused the read, so the key it keeps for the report was never looked at; observed: \(locked.path) is a file of \(key.count) bytes; the operating system answered The file “locked.json” couldn’t be opened because you don’t have permission to view it. (NSCocoaErrorDomain 257): The operation couldn’t be completed. Permission denied (NSPOSIXErrorDomain 13)",
            fix: "let the user running wisent-errors-test read it (chmod u+r \(locked.path)): it holds the only copy of the report's key, which reads its replies; nothing in wisent-errors-test writes it again, so if it cannot be read, remove \(locked.path) and file the report again with `wisent-errors-test support report` or from an app's Report a Problem window"))
        XCTAssertEqual(try Data(contentsOf: locked), key, "the refused key is left as it was")
        XCTAssertEqual(try tree(state), ["support", "support/locked.json"], "reading the keys kept nothing more")
    }

    /// `support report` to an address of the real public support host that
    /// is not its reports endpoint (/robots.txt, where posting files nothing):
    /// the host's answer, a page of text with line ends in it, is quoted as one
    /// JSON string inside the sentence, so the refusal stays three lines. The
    /// page carries a request id of its own each time, so the quoted text is
    /// read back as JSON and compared by its fixed start and end.
    func test_support_report_quotes_an_answer_that_is_not_supports_on_one_line() throws {
        let robots = "https://support.wisent.com/robots.txt"
        let ran = try run(report("something failed"), environment: telemetry(["WISENT_SUPPORT_URL": robots]))
        XCTAssertEqual(ran.status, 69, "\(ran)")
        XCTAssertEqual(ran.stdout, "")
        let lines = ran.stderr.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4, "three lines, the answer inside the first: \(ran.stderr)")
        let prefix = "Error: reading support's answer at \(robots): the answer is not a support service's: "
        let suffix = "; observed: HTTP 404"
        let first = try XCTUnwrap(lines.first)
        XCTAssertTrue(first.hasPrefix(prefix) && first.hasSuffix(suffix), first)
        let quoted = try JSONSerialization.jsonObject(with: Data(first.dropFirst(prefix.count).dropLast(suffix.count).utf8), options: [.fragmentsAllowed])
        let page = try XCTUnwrap(quoted as? String, "the answer is quoted as a JSON string: \(first)")
        XCTAssertTrue(page.hasPrefix("The page could not be found\n\nNOT_FOUND\n\n") && page.hasSuffix("\n"), page)
        XCTAssertEqual(Array(lines.dropFirst()), [
            "fix: check that \(robots) is a support service's /v1/public/reports",
            "cause: wisent-errors.support.exchange.support-answer-unreadable; https://github.com/wisent-ai/wisent-errors/blob/main/docs/errors/telemetry.md#wisent-errors-support-exchange-support-answer-unreadable",
            "",
        ])
        XCTAssertEqual(try keptOnDisk(), [], "no key is kept for a report never filed")
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
