// What every Swift telemetry case shares: its own directory under the
// checkout's .build, removed when it ends, named to the library through its
// own WISENT_TELEMETRY_HOME; the process variables the library reads, unset
// before each case; a failure the way a product raises one; and asking the
// transport the same way the library does, so a sentence that quotes the
// transport or another component is compared whole.

import Foundation
import XCTest
import WisentErrors

/// A case that needs a real component the environment does not name: it
/// fails naming the variable, never passes.
struct Blocked: Error, CustomStringConvertible {
    let description: String
}

/// What one request answered: the status and body, or the transport's failure as `explained` says it.
struct Answered {
    let status: Int
    let body: String
    let failure: String?
}

class TelemetryCase: XCTestCase {
    /// The checkout's build directory: tests/telemetry/swift/<this file> is four levels below the checkout.
    static let build = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build")

    /// The discard port on loopback, where nothing listens on a host that
    /// runs no discard service: https://www.rfc-editor.org/rfc/rfc863
    static let nothingListens = "http://127.0.0.1:9/api/analytics/mobile/collect"

    private(set) var root: URL!
    /// The case's WISENT_TELEMETRY_HOME.
    var state: URL { root.appendingPathComponent("state") }

    private static let variables = ["WISENT_TELEMETRY_COLLECTOR_URL", "WISENT_SUPPORT_URL", "DO_NOT_TRACK"]

    override func setUpWithError() throws {
        root = Self.build.appendingPathComponent("telemetry-swift").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for variable in Self.variables { unsetenv(variable) }
    }

    override func tearDownWithError() throws {
        for variable in Self.variables { unsetenv(variable) }
        try FileManager.default.removeItem(at: root)
    }

    func telemetry(app: String, home: URL? = nil) -> WisentTelemetry {
        WisentTelemetry(
            product: TelemetryProduct(id: "wisent-errors-test", appID: app, version: "0.0.0"),
            environment: ["WISENT_TELEMETRY_HOME": (home ?? state).path])
    }

    /// A failure the way a product raises one, with the home directory in its detail and remedy.
    func sampleFailure() throws -> Failure {
        try Failure(failurePoint: "wisent-errors-test.pairs.import", code: .notFound, service: "wisent-errors-test")
            .detail("reading \(NSHomeDirectory())/pairs/calm.json: no such file")
            .remedy("write \(NSHomeDirectory())/pairs/calm.json first")
    }

    /// Report `failure` and wait until the send it starts has ended.
    func settle(_ telemetry: WisentTelemetry, _ failure: Failure, causeID: String? = nil) {
        let done = expectation(description: "the failure settled")
        telemetry.failure(failure, causeID: causeID) { done.fulfill() }
        wait(for: [done], timeout: 60)
    }

    /// The file at `url`, read from disk as the JSON object telemetry wrote.
    func object(_ url: URL) throws -> [String: Any] {
        let read = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(read as? [String: Any], "\(url.path) holds a JSON object")
    }

    /// The ids of the events waiting on disk, from the queue's file names.
    func queuedOnDisk() throws -> [String] {
        let queue = state.appendingPathComponent("queue")
        guard FileManager.default.fileExists(atPath: queue.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: queue.path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(".json".count)) }.sorted()
    }

    /// The value of `name`, or the case fails naming it.
    func required(_ name: String, _ meaning: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw Blocked(description: "blocked, not passed: \(name) is not set; set it to \(meaning): this case runs against the real one")
        }
        return value
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
    func ask(_ address: String, posting body: Data) async throws -> Answered {
        var request = URLRequest(url: try XCTUnwrap(URL(string: address), address))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral)
        return await withCheckedContinuation { answered in
            session.dataTask(with: request) { data, response, error in
                answered.resume(returning: Answered(
                    status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    body: data.map { String(decoding: $0, as: UTF8.self) } ?? "",
                    failure: error?.explained))
            }.resume()
        }
    }

    /// The one event waiting in `telemetry`'s queue, exactly as it is sent.
    func onlyEvent(_ telemetry: WisentTelemetry) throws -> (id: String, body: Data) {
        let queued = try telemetry.queued()
        XCTAssertEqual(queued.count, 1, "one event waits")
        let event = try XCTUnwrap(queued.first)
        let id = try XCTUnwrap(event["eventId"] as? String)
        XCTAssertEqual(try queuedOnDisk(), [id], "the event is the one file of the queue on disk")
        return (id, try JSONSerialization.data(withJSONObject: event))
    }
}
