// The Swift telemetry's consent and store, through the package's public API
// and read back from the files it keeps: nothing is queued before the user
// answers, the command line's consent is the app's, the same failure again
// is a repeat counted in a row, turning off drops what waits, and every file
// it cannot keep or read is refused with its whole sentence -- the cases
// tests/telemetry/consent.rs and store.rs hold the Rust client to.
//
//   swift test --filter ConsentAndStoreTests

import Foundation
import XCTest
import WisentErrors

final class ConsentAndStoreTests: TelemetryCase {
    private var consent: URL { state.appendingPathComponent("consent.json") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A failure queued at level errors is sent at once: to nothing here.
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", Self.nothingListens, 1)
    }

    func test_nothing_is_queued_before_the_user_answers() throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        settle(telemetry, try sampleFailure(), causeID: "pairs-unreadable")
        XCTAssertEqual(telemetry.status()["level"] as? String, "unanswered")
        XCTAssertEqual(try telemetry.queued().count, 0)
        XCTAssertEqual(try queuedOnDisk(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.appendingPathComponent("installation.json").path), "no id is made before consent")
        XCTAssertFalse(FileManager.default.fileExists(atPath: consent.path), "no answer is written for the user")
    }

    func test_the_command_lines_consent_is_the_apps_consent() throws {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try Data(#"{"level":"errors","answered_at":"2000-01-01T00:00:00Z"}"#.utf8).write(to: consent)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        XCTAssertEqual(try telemetry.level(), .errors)
        settle(telemetry, try sampleFailure(), causeID: "pairs-unreadable")
        let ids = try queuedOnDisk()
        XCTAssertEqual(ids.count, 1, "one event waits on disk")
        let event = try object(state.appendingPathComponent("queue").appendingPathComponent("\(ids.first ?? "").json"))
        XCTAssertEqual(event["eventId"] as? String, ids.first)
        XCTAssertEqual(event["appId"] as? String, "wisent-errors-test-desktop")
        XCTAssertEqual(event["eventName"] as? String, "failure")
        XCTAssertEqual(event["anonymousId"] as? String, try object(state.appendingPathComponent("installation.json"))["id"] as? String)
        let properties = try XCTUnwrap(event["properties"] as? [String: Any])
        XCTAssertEqual(properties["failure_point"] as? String, "wisent-errors-test.pairs.import")
        XCTAssertEqual(properties["error_code"] as? String, "not_found")
        XCTAssertEqual(properties["cause_id"] as? String, "pairs-unreadable")
        XCTAssertEqual(properties["detail"] as? String, "reading ~/pairs/calm.json: no such file", "the home directory is taken out of what is queued")
        XCTAssertEqual(properties["remedy"] as? String, "write ~/pairs/calm.json first")
    }

    func test_the_same_failure_again_is_a_repeat_counted_in_a_row() throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        for _ in 1...3 { settle(telemetry, try sampleFailure()) }
        let queued = try telemetry.queued()
        XCTAssertEqual(try queuedOnDisk().count, 5, "three failures and two repeats wait on disk")
        XCTAssertEqual(queued.filter { $0["eventName"] as? String == "failure" }.count, 3)
        let repeats = queued.filter { $0["eventName"] as? String == "frustration.repeat_failure" }
            .compactMap { $0["properties"] as? [String: Any] }
        XCTAssertEqual(repeats.compactMap { $0["consecutive"] as? Int }.sorted(), [2, 3])
        XCTAssertEqual(repeats.compactMap { $0["failure_point"] as? String }, ["wisent-errors-test.pairs.import", "wisent-errors-test.pairs.import"])
        XCTAssertEqual(repeats.compactMap { ($0["seconds_since_previous"] as? Int).map { $0 >= 0 } }, [true, true])
        let last = try XCTUnwrap(try object(state.appendingPathComponent("signals.json"))["last_failure"] as? [String: Any])
        XCTAssertEqual(last["failure_point"] as? String, "wisent-errors-test.pairs.import")
        XCTAssertEqual(last["consecutive"] as? Int, 3)
    }

    func test_turning_off_drops_what_waits() throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        XCTAssertEqual(try queuedOnDisk().count, 1)
        try telemetry.setLevel(.off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.appendingPathComponent("queue").path), "the queue is removed")
        XCTAssertEqual(try object(consent)["level"] as? String, "off")
        XCTAssertEqual(telemetry.status()["level"] as? String, "off")
        XCTAssertEqual(telemetry.status()["queued"] as? Int, 0)
    }

    // Defect EB65B832: turning telemetry off kept the queued events without a
    // word when the queue's removal failed (`try?`). The failure is thrown
    // whole, and the events it could not remove are still there to be seen.
    func test_turning_off_names_a_queue_it_cannot_remove() throws {
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        let queue = state.appendingPathComponent("queue")
        // Owner read and search, no write, so no entry of it can be removed:
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: queue.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: queue.path) }
        var os = ""
        do {
            try FileManager.default.removeItem(at: queue)
            XCTFail("a queue without write permission was removed")
        } catch {
            os = error.explained
        }
        XCTAssertThrowsError(try telemetry.setLevel(.off)) { error in
            XCTAssertEqual(
                "\(error)",
                "keeping the event queue in \(queue.path): the telemetry directory could not be written: \(os); observed: directory \(state.path); fix: make \(state.path) writable by this user, or name a writable one with WISENT_TELEMETRY_HOME")
        }
        XCTAssertEqual(try queuedOnDisk().count, 1, "the event the removal could not reach is still queued")
    }

    func test_an_unwritable_directory_is_named_and_nothing_is_lost_silently() throws {
        let blocker = root.appendingPathComponent("a-file")
        try Data("not a directory".utf8).write(to: blocker)
        let home = blocker.appendingPathComponent("telemetry")
        let telemetry = telemetry(app: "wisent-errors-test-desktop", home: home)
        var os = ""
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: home.path, isDirectory: true), withIntermediateDirectories: true)
            XCTFail("a directory under a file was made")
        } catch {
            os = error.explained
        }
        XCTAssertThrowsError(try telemetry.setLevel(.errors)) { error in
            XCTAssertEqual(
                "\(error)",
                "keeping the telemetry consent in \(home.path)/consent.json: the telemetry directory could not be written: \(os); observed: directory \(home.path); fix: make \(home.path) writable by this user, or name a writable one with WISENT_TELEMETRY_HOME")
        }
        settle(telemetry, try sampleFailure())
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path), "nothing was written under the blocking file")
    }

    func test_a_damaged_consent_file_is_refused_and_nothing_is_sent() async throws {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        // Spaced and with a second key, so the file is longer than its object
        // written again compactly: the refusal must name the file's own size.
        let damaged = Data("{ \"level\" : \"sometimes\",\n  \"answered_at\" : \"never\" }\n".utf8)
        try damaged.write(to: consent)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        let refusal = "reading the telemetry consent from \(consent.path): the file is not what telemetry wrote: level \"sometimes\" is not off, errors or usage; observed: the file holds \(damaged.count) bytes; fix: answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove \(consent.path)"
        XCTAssertThrowsError(try telemetry.level()) { error in XCTAssertEqual("\(error)", refusal) }
        settle(telemetry, try sampleFailure())
        XCTAssertEqual(try queuedOnDisk(), [], "nothing is queued under a consent telemetry did not write")
        let delivered = await telemetry.flush()
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.stopped, refusal)
        let kept = try object(state.appendingPathComponent("delivery.json"))
        XCTAssertEqual((kept["stopped"] as? [String: Any])?["detail"] as? String, refusal)
        XCTAssertEqual(try Data(contentsOf: consent), damaged, "the damaged file is left as it was")
    }

    func test_a_file_the_system_refuses_to_read_is_named_with_its_answer() throws {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let written = Data(#"{"level":"errors"}"#.utf8)
        try written.write(to: consent)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        // No permission for anyone: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: consent.path)
        var refused = ""
        XCTAssertThrowsError(try telemetry.level()) { error in refused = "\(error)" }
        let os = readRefusal(consent)
        // Owner read and write, given back.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: consent.path)
        let path = consent.path
        XCTAssertEqual(
            refused,
            "reading the telemetry consent from \(path): the operating system refused the read, so what the file holds was never looked at; observed: \(path) is a file of \(written.count) bytes; the operating system answered \(os); fix: let the user running wisent-errors-test read it (chmod u+r \(path)), or remove \(path) so telemetry writes it again")
        XCTAssertEqual(try Data(contentsOf: consent), written, "the refused file is left as it was")

        // A directory where the file belongs is refused the same way.
        try FileManager.default.removeItem(at: consent)
        try FileManager.default.createDirectory(at: consent, withIntermediateDirectories: false)
        XCTAssertThrowsError(try telemetry.level()) { error in
            XCTAssertEqual(
                "\(error)",
                "reading the telemetry consent from \(path): the operating system refused the read, so what the file holds was never looked at; observed: \(path) is a directory; the operating system answered \(readRefusal(consent)); fix: let the user running wisent-errors-test read it (chmod u+r \(path)), or remove \(path) so telemetry writes it again")
        }
    }

    /// What the operating system answers this process reading `url`, as `explained` says it.
    private func readRefusal(_ url: URL) -> String {
        do {
            _ = try Data(contentsOf: url)
            return "nothing: the read succeeded"
        } catch {
            return error.explained
        }
    }
}
