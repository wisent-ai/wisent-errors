// `wisent-errors-swift telemetry flush` and `telemetry show`, the package's
// command line sending a product's queued telemetry and showing it exactly
// as it will go, as its app's Settings window does (`WisentTelemetry`,
// docs/telemetry.md), run as a process and read back from the queue and
// `delivery.json` on disk: what never reaches a collector
// (UnreachedDeliveryTests: nothing answered yet, a plain-http address
// refused by name, nothing listening, DO_NOT_TRACK, a consent telemetry did
// not write, turning off; and every queue entry `show` cannot read), and
// what the real Echo app collector answers (ReachedDeliveryTests, and
// FailingDeliveryTests for a collector deployment failing on its side) --
// the cases tests/telemetry/delivery/ holds the Rust client to.
//
//   swift test --filter UnreachedDeliveryTests
//   swift test --filter ReachedDeliveryTests
//   swift test --filter FailingDeliveryTests
//
// Rule 4: each case runs the built wisent-errors-swift (CommandCase.swift).
// Nothing stands in for a collector: UnreachedDeliveryTests sends to the
// discard port on loopback, where nothing listens, so the refusal it reads
// is the real transport's; every case that needs a collector to answer
// sends to the real Echo app collector WISENT_TELEMETRY_TEST_COLLECTOR names
// (and an app its MOBILE_ANALYTICS_APPS_JSON declares,
// WISENT_TELEMETRY_TEST_APP_ID), or to a deployment failing on its side,
// WISENT_TELEMETRY_TEST_FAILING_COLLECTOR, and fails as blocked naming the
// variable when it is not set, never passes. Where a sentence quotes the
// transport or the collector, the case asks it the same way in this process
// and compares the whole sentence.
// Rule 8: the command's environment is cleared and given only HOME,
// CFFIXED_USER_HOME, TMPDIR and XDG_* inside the case's directory under
// .build, and the product's own backend variables, set on each run in the
// case itself: WISENT_TELEMETRY_HOME (the directory the queue and
// `delivery.json` are read back from, inside the case's own),
// WISENT_TELEMETRY_COLLECTOR_URL and DO_NOT_TRACK. They are the only
// backends telemetry has; nothing of the operator's is read or written.
// Rule 9: the command cannot be built here, so no sentence was probed: each
// expected refusal is the cause's template in catalogue/failures/telemetry.json
// rendered whole with the values the case observes.

#if os(macOS)
import Foundation
import XCTest

class DeliveryCase: TelemetryCase {
    /// What `telemetry flush` printed: sent, remaining and skipped.
    func flushed(_ ran: Ran) throws -> NSDictionary {
        try XCTUnwrap(try printed(ran) as? NSDictionary, ran.stdout)
    }

    /// The outcome `delivery.json` keeps of the last flush under `home`.
    func lastDelivery(_ home: URL? = nil) throws -> [String: Any] {
        // fallback: the case's own telemetry home unless another is named.
        try object((home ?? state).appendingPathComponent("delivery.json"))
    }

    /// The one line a stopped flush keeps in `delivery.json`.
    func stopped(_ home: URL? = nil) throws -> String? {
        (try lastDelivery(home)["stopped"] as? [String: Any])?["detail"] as? String
    }

    /// The refusal a flush stopped with: its three lines, and the line `delivery.json` keeps.
    func deliver(_ cause: String, _ sentence: String, fix: String) -> (lines: String, kept: String) {
        (refusal("wisent-errors.telemetry.deliver", cause, page: "telemetry", sentence, fix: fix), "\(sentence); fix: \(fix)")
    }
}

final class UnreachedDeliveryTests: DeliveryCase {
    func test_telemetry_flush_keeps_what_no_collector_took_with_why() throws {
        let unreachable = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens])
        let flush = ["telemetry", "flush"] + product()

        // Nothing answered, nothing waiting: nothing is sent and nothing kept.
        let unanswered = try run(flush, environment: unreachable)
        XCTAssertEqual(unanswered.status, 0, "\(unanswered)")
        XCTAssertEqual(unanswered.stderr, "")
        XCTAssertEqual(try flushed(unanswered), ["sent": 0, "remaining": 0, "skipped": "unanswered"] as NSDictionary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path), "a skipped flush keeps nothing")

        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: unreachable).status, 0)
        XCTAssertEqual(try run(failure(), environment: unreachable).status, 0)
        let event = try onlyEvent()

        // A plain-http address, refused by name before anything is sent.
        let plainAddress = "http://collector.example.com/api/analytics/mobile/collect"
        let invalid = deliver(
            "collector-invalid",
            "reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds \(plainAddress)",
            fix: "set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it")
        let plain = try run(flush, environment: telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": plainAddress]))
        XCTAssertEqual(plain.status, 1, "\(plain)")
        XCTAssertEqual(plain.stderr, invalid.lines)
        XCTAssertEqual(try flushed(plain), ["sent": 0, "remaining": 1, "skipped": NSNull()] as NSDictionary)
        XCTAssertEqual(try stopped(), invalid.kept)
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the event still waits")

        // Nothing listening: the transport's own failure, and the event kept.
        let why = try XCTUnwrap(try ask(Self.nothingListens, posting: event.body).failure, "nothing answers \(Self.nothingListens)")
        let unreached = deliver(
            "collector-unreachable",
            "sending event \(event.id) to \(Self.nothingListens): the collector could not be reached: \(why); observed: 1 event(s) stay queued",
            fix: "nothing to do: the events are sent on the next flush once the network or the collector is back")
        let nowhere = try run(flush, environment: unreachable)
        XCTAssertEqual(nowhere.status, 69, "\(nowhere)")
        XCTAssertEqual(nowhere.stderr, unreached.lines)
        XCTAssertEqual(try flushed(nowhere), ["sent": 0, "remaining": 1, "skipped": NSNull()] as NSDictionary)
        let kept = try lastDelivery()
        XCTAssertEqual(try stopped(), unreached.kept)
        XCTAssertEqual(kept["sent"] as? Int, 0)
        XCTAssertEqual(kept["remaining"] as? Int, 1)
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the event still waits")
        // When it was tried, as Settings shows it under "Last sent": this
        // host's local time with its offset, never a bare UTC `Z`.
        let at = try XCTUnwrap(kept["at"] as? String)
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxxxx"
        let moment = try XCTUnwrap(reader.date(from: at), "\(at) is RFC 3339 with an offset")
        let offset = TimeZone.current.secondsFromGMT(for: moment)
        XCTAssertEqual(
            String(at.suffix(6)), String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) % 3600 / 60),
            "\(at) is in this host's offset")

        // DO_NOT_TRACK: nothing is sent, whatever was answered.
        let untracked = try run(flush, environment: unreachable.merging(["DO_NOT_TRACK": "1"]) { $1 })
        XCTAssertEqual(untracked.status, 0, "\(untracked)")
        XCTAssertEqual(try flushed(untracked), ["sent": 0, "remaining": 1, "skipped": "DO_NOT_TRACK"] as NSDictionary)

        // A consent file telemetry did not write: nothing is sent, and the flush says why.
        let answered = try Data(contentsOf: consent)
        let damaged = Data("{ \"level\" : \"sometimes\" }\n".utf8)
        try damaged.write(to: consent)
        let unread = try run(flush, environment: unreachable)
        let sentence = "reading the telemetry consent from \(consent.path): the file is not what telemetry wrote: level \"sometimes\" is not off, errors or usage; observed: the file holds \(damaged.count) bytes"
        let fix = "answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove \(consent.path)"
        XCTAssertEqual(unread.status, 1, "\(unread)")
        XCTAssertEqual(unread.stderr, refusal("wisent-errors.telemetry.store", "file-unreadable", page: "telemetry", sentence, fix: fix))
        XCTAssertEqual(try flushed(unread), ["sent": 0, "remaining": 1, "skipped": NSNull()] as NSDictionary)
        XCTAssertEqual(try stopped(), "\(sentence); fix: \(fix)")
        XCTAssertEqual(try Data(contentsOf: consent), damaged, "the damaged file is left as it was")
        try answered.write(to: consent)

        // Turned off: what waited was dropped, and nothing is sent.
        XCTAssertEqual(try run(["telemetry", "set", "off"] + product(), environment: unreachable).status, 0)
        let off = try run(flush, environment: unreachable)
        XCTAssertEqual(off.status, 0, "\(off)")
        XCTAssertEqual(try flushed(off), ["sent": 0, "remaining": 0, "skipped": "off"] as NSDictionary)
        XCTAssertEqual(try queuedOnDisk(), [])
    }

    func test_telemetry_show_prints_the_queue_exactly_as_it_will_go() throws {
        let unreachable = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": Self.nothingListens])
        let show = ["telemetry", "show"] + product()

        let empty = try run(show, environment: unreachable)
        XCTAssertEqual(empty.status, 0, "\(empty)")
        XCTAssertEqual(try printed(empty) as? NSArray, [] as NSArray)

        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(), environment: unreachable).status, 0)
        XCTAssertEqual(try run(failure(), environment: unreachable).status, 0)
        let event = try onlyEvent()
        let one = try run(show, environment: unreachable)
        XCTAssertEqual(one.status, 0, "\(one)")
        XCTAssertEqual(one.stderr, "")
        XCTAssertEqual(try printed(one) as? NSArray, [try object(event.body, event.id)] as NSArray, "the event as the queue holds it on disk")

        // A queued event the system refuses to read: no permission for anyone.
        // https://pubs.opengroup.org/onlinepubs/9799919799/utilities/chmod.html
        let file = state.appendingPathComponent("queue").appendingPathComponent("\(event.id).json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        let os = answer { _ = try Data(contentsOf: file) }
        let refused = try run(show, environment: unreachable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertEqual(refused, telemetryRefusal(
            "wisent-errors.telemetry.store", "file-read-refused", status: 1,
            "reading a queued event from \(file.path): the operating system refused the read, so what the file holds was never looked at; observed: \(file.path) is a file of \(event.body.count) bytes; the operating system answered \(os)",
            fix: "let the user running wisent-errors-test read it (chmod u+r \(file.path)), or remove \(file.path) so telemetry writes it again"))
        XCTAssertEqual(try Data(contentsOf: file), event.body, "the refused event is left as it was")

        // A queued file telemetry did not write.
        let stray = state.appendingPathComponent("queue").appendingPathComponent("stray.json")
        try Data("[]".utf8).write(to: stray)
        XCTAssertEqual(try run(show, environment: unreachable), telemetryRefusal(
            "wisent-errors.telemetry.store", "file-unreadable", status: 1,
            "reading a queued event from \(stray.path): the file is not what telemetry wrote: it is not a JSON object; observed: the file holds 2 bytes",
            fix: "answer again, in an app's settings or with `wisent-errors-test telemetry on|off`, which rewrites it, or remove \(stray.path)"))
        XCTAssertEqual(try text(stray), "[]")
    }
}

final class ReachedDeliveryTests: DeliveryCase {
    func test_telemetry_flush_delivers_to_the_real_collector_or_keeps_its_refusal() throws {
        let address = try collector()
        let app = try required("WISENT_TELEMETRY_TEST_APP_ID", "an app the collector's MOBILE_ANALYTICS_APPS_JSON declares")
        let reached = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": address])

        // A declared app: the failure's own send delivers it, and a flush finds nothing left.
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(app), environment: reached).status, 0)
        XCTAssertEqual(try run(failure(app, ["--cause-id", "pairs-unreadable"]), environment: reached), Ran(status: 0, stdout: "", stderr: ""))
        let delivered = try lastDelivery()
        XCTAssertEqual(delivered["sent"] as? Int, 1)
        XCTAssertEqual(delivered["remaining"] as? Int, 0)
        XCTAssertTrue(delivered["stopped"] is NSNull, "\(delivered)")
        XCTAssertEqual(try queuedOnDisk(), [], "the accepted event left the queue")
        let after = try run(["telemetry", "flush"] + product(app), environment: reached)
        XCTAssertEqual(after.status, 0, "\(after)")
        XCTAssertEqual(try flushed(after), ["sent": 0, "remaining": 0, "skipped": NSNull()] as NSDictionary)

        // An app the collector does not declare: its HTTP 403
        // (https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.4) with its declared cause.
        let undeclared = root.appendingPathComponent("undeclared")
        let elsewhereApp = "wisent-errors-test-undeclared"
        let toUndeclared = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": address], home: undeclared)
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(elsewhereApp), environment: toUndeclared).status, 0)
        let queued = try run(failure(elsewhereApp), environment: toUndeclared)
        let event = try onlyEvent(undeclared)
        let answer = try ask(address, posting: event.body)
        XCTAssertEqual(answer.status, 403, answer.body)
        XCTAssertEqual((try object(Data(answer.body.utf8), answer.body))["cause"] as? String, "app-undeclared", answer.body)
        let refused = deliver(
            "collector-refused",
            "sending event \(event.id) to \(address): the collector refused HTTP 403: \(answer.body); observed: 1 event(s) stay queued",
            fix: "the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app \(elsewhereApp) in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush")
        XCTAssertEqual(queued, Ran(status: 0, stdout: "", stderr: said(refused.kept)), "the failure's own send says the refusal, and the command goes on")
        let flushed403 = try run(["telemetry", "flush"] + product(elsewhereApp), environment: toUndeclared)
        XCTAssertEqual(flushed403.status, 1, "\(flushed403)")
        XCTAssertEqual(flushed403.stderr, refused.lines)
        XCTAssertEqual(try flushed(flushed403), ["sent": 0, "remaining": 1, "skipped": NSNull()] as NSDictionary)
        XCTAssertEqual(try stopped(undeclared), refused.kept)
        XCTAssertEqual(try queuedOnDisk(undeclared), [event.id], "the refused event still waits")

        // An address that is not a collector: its answer named, the event kept.
        let robots = try origin(address, before: "/api/") + "/robots.txt"
        let toRobots = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": robots], home: undeclared)
        let notCollector = try ask(robots, posting: event.body)
        let unreadable = deliver(
            "collector-answer-unreadable",
            "reading the collector's answer to event \(event.id): the answer is not the collector's {\"ok\": true}: \(notCollector.body); observed: HTTP \(notCollector.status) from \(robots)",
            fix: "check that \(robots) is the Echo app collector, /api/analytics/mobile/collect")
        let elsewhere = try run(["telemetry", "flush"] + product(elsewhereApp), environment: toRobots)
        XCTAssertEqual(elsewhere.status, 69, "\(elsewhere)")
        XCTAssertEqual(elsewhere.stderr, unreadable.lines)
        XCTAssertEqual(try stopped(undeclared), unreadable.kept)
        XCTAssertEqual(try queuedOnDisk(undeclared), [event.id], "the event still waits")
    }
}

final class FailingDeliveryTests: DeliveryCase {
    func test_telemetry_flush_keeps_the_events_a_collector_failing_on_its_side_did_not_take() throws {
        let failing = try required(
            "WISENT_TELEMETRY_TEST_FAILING_COLLECTOR",
            "a collector deployment that answers with a server error, such as an Echo that cannot reach its database")
        // The collector checks the app before it writes: only an app it
        // declares reaches the store that fails.
        let app = try required("WISENT_TELEMETRY_TEST_APP_ID", "an app the collector's MOBILE_ANALYTICS_APPS_JSON declares")
        let toFailing = telemetry(["WISENT_TELEMETRY_COLLECTOR_URL": failing])
        XCTAssertEqual(try run(["telemetry", "set", "errors"] + product(app), environment: toFailing).status, 0)
        XCTAssertEqual(try run(failure(app), environment: toFailing).status, 0)
        let event = try onlyEvent()
        // The 5xx server error class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
        let answer = try ask(failing, posting: event.body)
        XCTAssertTrue((500..<600).contains(answer.status), "\(answer.status) \(answer.body)")
        let failed = deliver(
            "collector-failed",
            "sending event \(event.id) to \(failing): the collector failed on its own side, HTTP \(answer.status): \(answer.body); observed: 1 event(s) stay queued",
            fix: "nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `wisent-errors-test support report`, or from an app's Help → Report a Problem")
        let ran = try run(["telemetry", "flush"] + product(app), environment: toFailing)
        XCTAssertEqual(ran.status, 69, "\(ran)")
        XCTAssertEqual(ran.stderr, failed.lines)
        XCTAssertEqual(try flushed(ran), ["sent": 0, "remaining": 1, "skipped": NSNull()] as NSDictionary)
        XCTAssertEqual(try stopped(), failed.kept)
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the event still waits")
    }
}
#endif
