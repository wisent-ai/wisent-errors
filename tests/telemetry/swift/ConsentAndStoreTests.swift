// `wisent-errors-swift telemetry set|failure|status`, the package's command
// line keeping a product's telemetry the way its app keeps it
// (`WisentTelemetry`, docs/telemetry.md), run as a process and read back
// from the files it keeps: the user's answer, and turning off dropping what
// waits; a failure queued only once the user agreed, with the home directory
// taken out, the same failure again counted as a repeat, nothing queued
// under DO_NOT_TRACK or a consent telemetry did not write; and the status
// an installation says of itself -- the cases tests/telemetry/consent.rs
// and store.rs hold the Rust client to.
//
//   swift test --filter ConsentAndStoreTests
//
// Rule 4: every `run(...)` below is CommandCase.run
// (tests/swift-cli/CommandCase.swift), which starts the executable
// `swift test` built from swift/Sources/wisent-errors-swift as a child
// process -- `process.executableURL = Self.executable` (CommandCase.swift:173),
// then `try process.run()` (CommandCase.swift:195) -- as an operator at a
// product's terminal runs it; nothing of the library is called here. The
// stories these cases tell are `telemetry set`, `failure` and `status`: what
// is kept on disk (the answer, the queue, the repeat count, the installation
// id), each read back from the files. A failure's own send goes to a real
// address, a loopback port where no process listens (RFC 863's discard
// port), so the real transport fails in the child and its whole sentence is
// read from stderr; no server, stub or canned answer stands in for a
// collector anywhere, and the event stays queued so the queue on disk can
// be read. The network effect itself, an event the real Echo app collector
// takes (WISENT_TELEMETRY_TEST_COLLECTOR, .wisent-release.json `env`), is
// `telemetry flush`'s story and ReachedDeliveryTests' (DeliveryTests.swift).
// Rule 8: the command's environment is cleared and given only HOME,
// CFFIXED_USER_HOME, TMPDIR and XDG_* inside the case's directory under
// .build, and the product's own backend variables, set on each run in the
// case itself: WISENT_TELEMETRY_HOME (the directory every file below is in),
// WISENT_TELEMETRY_COLLECTOR_URL and DO_NOT_TRACK. They are the only
// backends telemetry has; nothing of the operator's is read or written.
// Rule 9: every sentence, file and exit status below was copied from live
// runs of wisent-errors-swift built from this tree (`swift build --product
// wisent-errors-swift`, 2026-11-21): each step run by hand under `env -i`
// given only HOME, CFFIXED_USER_HOME, TMPDIR, XDG_* and the case's
// WISENT_TELEMETRY_HOME, WISENT_TELEMETRY_COLLECTOR_URL and DO_NOT_TRACK
// inside target/probe-swift/consent*, the queue chmod 500, the damaged files
// written byte for byte as here, and the files read back after each step.
// The transport's and the operating system's words are the ones those runs
// printed (TelemetryCase.unconnected).

#if os(macOS)
import Foundation
import XCTest

final class ConsentAndStoreTests: TelemetryCase {
    private var queue: URL { state.appendingPathComponent("queue") }

    /// The stderr line of the send a queued failure starts, when nothing listens and `waiting` events stay queued.
    private func unreached(_ id: String, _ waiting: Int) -> String {
        said("sending event \(id) to \(Self.nothingListens): the collector could not be reached: \(Self.unconnected); observed: \(waiting) event(s) stay queued; fix: nothing to do: the events are sent on the next flush once the network or the collector is back")
    }

    func test_telemetry_set_keeps_the_answer_the_app_and_the_command_line_share() throws {
        let unreachable = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens])

        // A level that is none, and no level at all.
        XCTAssertEqual(try run(["telemetry", "set", "sometimes"] + product(), environment: telemetry()), usage(
            "value-unknown",
            "reading the level of `wisent-errors-swift telemetry set`: \"sometimes\" is not one of its values; observed: its values: off, errors, usage",
            fix: "give the level one of off, errors, usage"))
        XCTAssertEqual(try run(["telemetry", "set"] + product(), environment: telemetry()), usage(
            "operands-wrong",
            "reading the operands of `wisent-errors-swift telemetry set`: it takes <off|errors|usage>, and 0 were given; observed: operands: none",
            fix: "run it as `wisent-errors-swift telemetry set <off|errors|usage>`"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "a refused answer kept nothing")

        // The answer, kept where the app reads it.
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: telemetry()), Ran(status: 0, stdout: "wisent-errors-test telemetry: errors\n", stderr: ""))
        XCTAssertEqual(try object(consent)["level"] as? String, "errors")
        XCTAssertNotNil(try object(consent)["answered_at"] as? String)
        XCTAssertEqual(try tree(state), ["consent.json"])

        // Turning off drops what waits.
        XCTAssertEqual(try run(failure(), environment: unreachable).status, 0)
        XCTAssertEqual(try queuedOnDisk().count, 1)
        XCTAssertEqual(try run(["telemetry", "set", "off"] + product(), environment: telemetry()), Ran(status: 0, stdout: "wisent-errors-test telemetry: off\n", stderr: ""))
        XCTAssertEqual(try object(consent)["level"] as? String, "off")
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.path), "the queue is removed")

        // A queue it cannot remove: owner read and search, no write, so no
        // entry of it can be removed.
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: telemetry()).status, 0)
        XCTAssertEqual(try run(failure(), environment: unreachable).status, 0)
        let waiting = try queuedOnDisk()
        XCTAssertEqual(waiting.count, 2, "the failure and its repeat wait: signals.json still holds the first, which turning off keeps")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: queue.path)
        // What the operating system answered the live run's removal, the queue's own name quoted.
        let os = "“queue” couldn’t be removed because you don’t have permission to access it. (NSCocoaErrorDomain 513): The operation couldn’t be completed. Permission denied (NSPOSIXErrorDomain 13)"
        let refused = try run(["telemetry", "set", "off"] + product(), environment: telemetry())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: queue.path)
        XCTAssertEqual(refused, telemetryRefusal(
            "wisent-errors.telemetry.store", "store-unwritable", status: 1,
            "keeping the event queue in \(queue.path): the telemetry directory could not be written: \(os); observed: directory \(state.path)",
            fix: "make \(state.path) writable by this user, or name a writable one with WISENT_TELEMETRY_HOME"))
        XCTAssertEqual(try object(consent)["level"] as? String, "off", "the answer was kept before the queue was reached")
        XCTAssertEqual(try queuedOnDisk(), waiting, "the event the removal could not reach is still queued")

        // A telemetry home it cannot make: a file stands where its directory would be.
        let blocker = root.appendingPathComponent("a-file")
        try Data("not a directory".utf8).write(to: blocker)
        let blocked = blocker.appendingPathComponent("telemetry")
        // What the operating system answered the live run making the directory: the file in the way, in the case's own directory.
        let made = "The file “a-file” couldn’t be saved in the folder “\(root.lastPathComponent)”. (NSCocoaErrorDomain 512): The operation couldn’t be completed. Not a directory (NSPOSIXErrorDomain 20)"
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: telemetry(home: blocked)), telemetryRefusal(
            "wisent-errors.telemetry.store", "store-unwritable", status: 1,
            "keeping the telemetry consent in \(blocked.path)/consent.json: the telemetry directory could not be written: \(made); observed: directory \(blocked.path)",
            fix: "make \(blocked.path) writable by this user, or name a writable one with WISENT_TELEMETRY_HOME"))
        XCTAssertEqual(try text(blocker), "not a directory", "the file in the way is left as it was")
    }

    func test_telemetry_failure_queues_only_what_the_user_agreed_to_send() throws {
        let unreachable = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens])

        // What a failure needs, and a point no runtime would build.
        XCTAssertEqual(try run(["telemetry", "failure"] + product() + ["--code", "not_found", "--service", "wisent-errors-test"], environment: unreachable), usage(
            "option-required",
            "reading the options of `wisent-errors-swift telemetry failure`: it needs --point, and --point was not given; observed: options given: --app, --app-version, --code, --product, --service",
            fix: "add --point, as in `--point ster.backend-start`"))
        XCTAssertEqual(
            try run(["telemetry", "failure"] + product() + ["--point", "wisent-errors-test..import", "--code", "not_found", "--service", "wisent-errors-test"], environment: unreachable),
            Ran(status: 2, stdout: "", stderr: refusal(
                "wisent_errors.envelope.build", "failure-point-segment-empty", page: "envelope",
                "building the failure envelope of service wisent-errors-test: segment 2 of the failure point \"wisent-errors-test..import\" is empty: two dots stand together, or a dot opens or ends it; observed: segments [\"wisent-errors-test\",\"\",\"import\"]",
                fix: "drop the extra dot, so every segment between dots holds a name, as in 'wisent-errors-test.import'; on an error path build it with Failure.orFallback")))

        // Before the user answers nothing is kept, not even an installation id.
        XCTAssertEqual(try run(failure(), environment: unreachable), Ran(status: 0, stdout: "", stderr: ""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "nothing is kept before the user answers")

        // Agreed: the failure waits, the home directory taken out, and the send it starts reaches nothing.
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: unreachable).status, 0)
        let first = try run(failure("wisent-errors-test-desktop", ["--cause-id", "pairs-unreadable"]), environment: unreachable)
        let event = try onlyEvent()
        XCTAssertEqual(first, Ran(status: 0, stdout: "", stderr: unreached(event.id, 1)))
        let queued = try object(event.body, event.id)
        XCTAssertEqual(queued["eventId"] as? String, event.id)
        XCTAssertEqual(queued["appId"] as? String, "wisent-errors-test-desktop")
        XCTAssertEqual(queued["eventName"] as? String, "failure")
        XCTAssertEqual(queued["appVersion"] as? String, "0.0.0")
        XCTAssertEqual(queued["anonymousId"] as? String, try object(state.appendingPathComponent("installation.json"))["id"] as? String)
        let properties = try XCTUnwrap(queued["properties"] as? [String: Any])
        XCTAssertEqual(properties["failure_point"] as? String, "wisent-errors-test.pairs.import")
        XCTAssertEqual(properties["error_code"] as? String, "not_found")
        XCTAssertEqual(properties["cause_id"] as? String, "pairs-unreadable")
        XCTAssertEqual(properties["detail"] as? String, "reading ~/pairs/calm.json: no such file", "the home directory is taken out of what is queued")
        XCTAssertEqual(properties["remedy"] as? String, "write ~/pairs/calm.json first")

        // The same failure again is a repeat, counted in a row; each send stops at the oldest event.
        XCTAssertEqual(try run(failure(), environment: unreachable), Ran(status: 0, stdout: "", stderr: unreached(event.id, 3)))
        XCTAssertEqual(try run(failure(), environment: unreachable), Ran(status: 0, stdout: "", stderr: unreached(event.id, 5)))
        let events = try queuedOnDisk().map { try object(queue.appendingPathComponent("\($0).json")) }
        XCTAssertEqual(events.filter { $0["eventName"] as? String == "failure" }.count, 3)
        let repeats = events.filter { $0["eventName"] as? String == "frustration.repeat_failure" }.compactMap { $0["properties"] as? [String: Any] }
        XCTAssertEqual(repeats.compactMap { $0["consecutive"] as? Int }.sorted(), [2, 3])
        XCTAssertEqual(repeats.compactMap { $0["failure_point"] as? String }, ["wisent-errors-test.pairs.import", "wisent-errors-test.pairs.import"])
        let last = try XCTUnwrap(try object(state.appendingPathComponent("signals.json"))["last_failure"] as? [String: Any])
        XCTAssertEqual(last["failure_point"] as? String, "wisent-errors-test.pairs.import")
        XCTAssertEqual(last["consecutive"] as? Int, 3)

        // DO_NOT_TRACK turns every level off: nothing more waits.
        let before = try queuedOnDisk()
        XCTAssertEqual(try run(failure(), environment: unreachable.merging(["DO_NOT_TRACK": "1"]) { $1 }), Ran(status: 0, stdout: "", stderr: ""))
        XCTAssertEqual(try queuedOnDisk(), before)

        // A consent file telemetry did not write: said on stderr, nothing queued, the command not failed by it.
        let damagedHome = root.appendingPathComponent("damaged")
        try FileManager.default.createDirectory(at: damagedHome, withIntermediateDirectories: true)
        let damagedConsent = damagedHome.appendingPathComponent("consent.json")
        // Spaced and with a second key, so the file is longer than its object
        // written again compactly: the refusal names the file's own size.
        let damaged = Data("{ \"level\" : \"sometimes\",\n  \"answered_at\" : \"never\" }\n".utf8)
        try damaged.write(to: damagedConsent)
        XCTAssertEqual(
            try run(failure(), environment: telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens], home: damagedHome)),
            Ran(status: 0, stdout: "", stderr: said("reading the telemetry consent from \(damagedConsent.path): the file is not what telemetry wrote: level \"sometimes\" is not off, errors or usage; observed: the file holds \(damaged.count) bytes; fix: answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove \(damagedConsent.path)")))
        XCTAssertEqual(try tree(damagedHome), ["consent.json"], "nothing is queued under a consent telemetry did not write")
        XCTAssertEqual(try Data(contentsOf: damagedConsent), damaged, "the damaged file is left as it was")
    }

    func test_telemetry_status_says_the_installation_as_its_files_hold_it() throws {
        let unreachable = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens])

        XCTAssertEqual(try run(["telemetry", "status", "--product", "wisent-errors-test"], environment: telemetry()), usage(
            "option-required",
            "reading the options of `wisent-errors-swift telemetry status`: it needs --app, and --app was not given; observed: options given: --product",
            fix: "add --app, as in `--app ster-desktop`"))

        // A fresh installation: unanswered, the public collector, nothing kept.
        let fresh = try run(["telemetry", "status"] + product(), environment: telemetry())
        XCTAssertEqual(fresh.status, 0, "\(fresh)")
        XCTAssertEqual(fresh.stderr, "")
        XCTAssertEqual(try printed(fresh) as? NSDictionary, [
            "product": "wisent-errors-test", "app_id": "wisent-errors-test-desktop", "level": "unanswered", "do_not_track": false,
            "collector": "https://telemetry.wisent.com/api/analytics/mobile/collect", "collector_source": "wisent-errors",
            "installation": NSNull(), "queued": 0, "last_delivery": NSNull(), "directory": state.path,
        ] as NSDictionary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "reading the status keeps nothing")

        // A collector address it refuses, said where the address would be.
        let address = "http://collector.example.com/api/analytics/mobile/collect"
        let plain = try run(["telemetry", "status"] + product(), environment: telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": address, "DO_NOT_TRACK": "1"]))
        let shown = try XCTUnwrap(try printed(plain) as? [String: Any], plain.stdout)
        XCTAssertTrue(shown["collector"] is NSNull, plain.stdout)
        XCTAssertEqual(shown["do_not_track"] as? Bool, true)
        XCTAssertEqual(
            (shown["collector_source"] as? [String: Any])?["refused"] as? String,
            "reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds \(address); fix: set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it")

        // An answered installation with one failure waiting and its last delivery, as the files hold them.
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: unreachable).status, 0)
        XCTAssertEqual(try run(failure(), environment: unreachable).status, 0)
        let kept = try run(["telemetry", "status"] + product(), environment: unreachable)
        XCTAssertEqual(kept.status, 0, "\(kept)")
        XCTAssertEqual(try printed(kept) as? NSDictionary, [
            "product": "wisent-errors-test", "app_id": "wisent-errors-test-desktop", "level": "errors", "do_not_track": false,
            "collector": Self.nothingListens, "collector_source": "WISENT_TELEMETRY_COLLECTOR_URL",
            "installation": try XCTUnwrap(try object(state.appendingPathComponent("installation.json"))["id"]),
            "queued": 1, "last_delivery": try object(state.appendingPathComponent("delivery.json")), "directory": state.path,
        ] as NSDictionary)

        // A file telemetry did not write is said as unreadable, never as no file.
        let installation = state.appendingPathComponent("installation.json")
        try Data("[]".utf8).write(to: installation)
        let damaged = try run(["telemetry", "status"] + product(), environment: unreachable)
        XCTAssertEqual(
            (try printed(damaged) as? [String: Any])?["installation"] as? NSDictionary,
            ["unreadable": "reading the installation id from \(installation.path): the file is not what telemetry wrote: it is not a JSON object; observed: the file holds 2 bytes; fix: answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove \(installation.path)"] as NSDictionary)
        XCTAssertEqual(try text(installation), "[]", "the damaged file is left as it was")

        // A consent file the system will not read: no permission for anyone. The status says it, and still answers.
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        let answer = try Data(contentsOf: consent)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: consent.path)
        let locked = try run(["telemetry", "status"] + product(), environment: unreachable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: consent.path)
        XCTAssertEqual(locked.status, 0, "\(locked)")
        XCTAssertEqual(locked.stderr, "")
        XCTAssertEqual(
            (try printed(locked) as? [String: Any])?["level"] as? NSDictionary,
            ["unreadable": "reading the telemetry consent from \(consent.path): the operating system refused the read, so what the file holds was never looked at; observed: \(consent.path) is a file of \(answer.count) bytes; the operating system answered The file “consent.json” couldn’t be opened because you don’t have permission to view it. (NSCocoaErrorDomain 257): The operation couldn’t be completed. Permission denied (NSPOSIXErrorDomain 13); fix: let the user running wisent-errors-test read it (chmod u+r \(consent.path)), or remove \(consent.path) so telemetry writes it again"] as NSDictionary)
        XCTAssertEqual(try Data(contentsOf: consent), answer, "the refused consent is left as it was")
        XCTAssertEqual(
            try tree(state), ["consent.json", "delivery.json", "installation.json", "queue", "queue/\(try XCTUnwrap(try queuedOnDisk().first)).json", "signals.json"],
            "reading the status kept nothing more")
    }
}
#endif
