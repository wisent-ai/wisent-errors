// What the telemetry and support cases of `wisent-errors-swift` share,
// beside CommandCase.swift's own directory and cleared environment: the
// product the command line names (`--product wisent-errors-test --app
// wisent-errors-test-desktop --app-version 0.0.0`, as an app's Info.plist
// names it); the product's own backend variables, the only ones the command
// has: WISENT_TELEMETRY_HOME (its files, a directory inside the case's own),
// WISENT_TELEMETRY_COLLECTOR_URL, WISENT_SUPPORT_URL and DO_NOT_TRACK, given
// to each run explicitly; a failure the way a product reports one, with the
// home directory in its detail; reading the files telemetry keeps back from
// disk; and asking the transport the same way the library does, so a
// sentence that quotes the transport or another component is compared whole.

#if os(macOS)
import Foundation
import XCTest

/// What one request answered: the status and body, or the transport's failure as `explained` says it.
struct Answered {
    let status: Int
    let body: String
    let failure: String?
}

class TelemetryCase: CommandCase {
    /// The discard port on loopback, where nothing listens on a host that
    /// runs no discard service: https://www.rfc-editor.org/rfc/rfc863
    static let nothingListens = "http://127.0.0.1:9/api/analytics/mobile/collect"

    /// The case's WISENT_TELEMETRY_HOME, made by the command when it first keeps something.
    var state: URL { root.appendingPathComponent("telemetry") }
    var consent: URL { state.appendingPathComponent("consent.json") }

    /// The product options every telemetry and support command takes, for `app`.
    func product(_ app: String = "wisent-errors-test-desktop") -> [String] {
        ["--product", "wisent-errors-test", "--app", app, "--app-version", "0.0.0"]
    }

    /// The case's environment with WISENT_TELEMETRY_HOME at `home` and the product's `variables`.
    func telemetry(_ variables: [String: String] = [:], home: URL? = nil) -> [String: String] {
        // fallback: a run naming no telemetry home keeps the case's own.
        environment.merging(["WISENT_TELEMETRY_HOME": (home ?? state).path]) { $1 }.merging(variables) { $1 }
    }

    /// `telemetry failure` of a failure the way a product reports one, with the home directory in its detail and remedy.
    func failure(_ app: String = "wisent-errors-test-desktop", _ more: [String] = []) -> [String] {
        ["telemetry", "failure"] + product(app) + [
            "--point", "wisent-errors-test.pairs.import", "--code", "not_found", "--service", "wisent-errors-test",
            "--detail", "reading \(home.path)/pairs/calm.json: no such file", "--remedy", "write \(home.path)/pairs/calm.json first",
        ] + more
    }

    /// A refusal of the telemetry or support functionality `operation` (catalogue/failures/telemetry.json).
    func telemetryRefusal(_ operation: String, _ cause: String, status: Int32, stdout: String = "", _ sentence: String, fix: String) -> Ran {
        Ran(status: status, stdout: stdout, stderr: refusal(operation, cause, page: "telemetry", sentence, fix: fix))
    }

    /// The line the library says on stderr for what telemetry could not keep or send, which never changes the command's status.
    func said(_ sentence: String) -> String {
        "wisent-errors: telemetry: \(sentence)\n"
    }

    /// The ids of the events waiting on disk under `home`, from the queue's file names.
    func queuedOnDisk(_ home: URL? = nil) throws -> [String] {
        // fallback: the case's own telemetry home unless another is named.
        let queue = (home ?? state).appendingPathComponent("queue")
        guard FileManager.default.fileExists(atPath: queue.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: queue.path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(".json".count)) }.sorted()
    }

    /// The one event waiting on disk: its id and the event as it will be sent.
    func onlyEvent(_ home: URL? = nil) throws -> (id: String, body: Data) {
        let ids = try queuedOnDisk(home)
        XCTAssertEqual(ids.count, 1, "one event waits on disk: \(ids)")
        let id = try XCTUnwrap(ids.first)
        // fallback: the case's own telemetry home unless another is named.
        return (id, try Data(contentsOf: (home ?? state).appendingPathComponent("queue").appendingPathComponent("\(id).json")))
    }

    /// The real Echo app collector, as tests/telemetry/main.rs names it.
    func collector() throws -> String {
        try required("WISENT_TELEMETRY_TEST_COLLECTOR", "the Echo app collector, https://<echo web>/api/analytics/mobile/collect")
    }

    /// The part of `address` before `marker`, its origin.
    func origin(_ address: String, before marker: String) throws -> String {
        let end = try XCTUnwrap(address.range(of: marker), "\(address) has the \(marker) path").lowerBound
        return String(address[..<end])
    }

    /// POST `body` to `address` as JSON through a session of its own, the
    /// way the library posts an event or a report, and say what answered.
    func ask(_ address: String, posting body: Data) throws -> Answered {
        var request = URLRequest(url: try XCTUnwrap(URL(string: address), address))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral)
        let done = expectation(description: "\(address) answered")
        var answered = Answered(status: 0, body: "", failure: "no answer")
        session.dataTask(with: request) { data, response, error in
            answered = Answered(
                // fallback: a request the transport failed has no status; 0 says none came.
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                // fallback: an answer with no body is the empty text.
                body: data.map { String(decoding: $0, as: UTF8.self) } ?? "",
                failure: error.map(self.explained))
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 120)
        return answered
    }

    /// stdout of a command that prints JSON, read as the object it holds.
    func printed(_ ran: Ran) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(ran.stdout.utf8))
    }
}
#endif
