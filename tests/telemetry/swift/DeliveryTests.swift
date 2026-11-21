// Delivery of the Swift telemetry through the package's public API, read back
// from the queue and `delivery.json` on disk: what never reaches a collector
// (UnreachedDeliveryTests: a plain-http address refused by name, nothing
// listening, the last delivery dated in local time) and what the real Echo
// app collector named by WISENT_TELEMETRY_TEST_COLLECTOR answers
// (ReachedDeliveryTests) -- the cases tests/telemetry/delivery/ holds the Rust
// client to. A sentence quoting the transport or the collector is compared
// whole, with those words read by asking them the same way.
//
//   swift test --filter UnreachedDeliveryTests
//   swift test --filter ReachedDeliveryTests

import Foundation
import XCTest
import WisentErrors

/// What a flush that stopped with one event still waiting says it observed.
private let oneWaits = "; observed: 1 event(s) stay queued"

final class UnreachedDeliveryTests: TelemetryCase {
    func test_a_plain_http_collector_is_refused_by_name() async throws {
        let address = "http://collector.example.com/api/analytics/mobile/collect"
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", address, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        let refusal = "reading the collector address from WISENT_TELEMETRY_COLLECTOR_URL: a collector address must be https://, or http:// on a loopback host; observed: WISENT_TELEMETRY_COLLECTOR_URL holds \(address); fix: set WISENT_TELEMETRY_COLLECTOR_URL to the https:// address of the Echo app collector, or unset it"
        XCTAssertThrowsError(try telemetry.collector()) { error in XCTAssertEqual("\(error)", refusal) }
        XCTAssertTrue(telemetry.status()["collector"] is NSNull)
        // A flush to the refused address sends nothing and keeps the refusal.
        let delivered = await telemetry.flush()
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.remaining, 1)
        XCTAssertEqual(delivered.stopped, refusal)
        XCTAssertEqual(try queuedOnDisk().count, 1, "the event still waits")
        let kept = try object(state.appendingPathComponent("delivery.json"))
        XCTAssertEqual((kept["stopped"] as? [String: Any])?["detail"] as? String, refusal)

        unsetenv("WISENT_TELEMETRY_COLLECTOR_URL")
        let public_ = try telemetry.collector()
        XCTAssertEqual(public_.url.absoluteString, "https://telemetry.wisent.com/api/analytics/mobile/collect")
        XCTAssertEqual(public_.source, "wisent-errors")
    }

    func test_an_unreachable_collector_keeps_the_events() async throws {
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", Self.nothingListens, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        let event = try onlyEvent(telemetry)
        let delivered = await telemetry.flush()
        let transport = try await ask(Self.nothingListens, posting: event.body)
        let why = try XCTUnwrap(transport.failure, "nothing answers \(Self.nothingListens)")
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.remaining, 1)
        let refusal = "sending event \(event.id) to \(Self.nothingListens): the collector could not be reached: \(why)\(oneWaits); fix: nothing to do: the events are sent on the next flush once the network or the collector is back"
        XCTAssertEqual(delivered.stopped, refusal)
        let kept = try object(state.appendingPathComponent("delivery.json"))
        XCTAssertEqual((kept["stopped"] as? [String: Any])?["detail"] as? String, refusal)
        XCTAssertEqual(kept["sent"] as? Int, 0)
        XCTAssertEqual(kept["remaining"] as? Int, 1)
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the event still waits")
    }

    /// `delivery.json` says when the last delivery was tried, which a person
    /// reads in Settings as "Last sent": in this host's local time with its
    /// offset, never a bare UTC `Z`.
    func test_the_last_delivery_says_when_in_local_time_with_its_offset() async throws {
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", Self.nothingListens, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        _ = await telemetry.flush()
        let at = try XCTUnwrap(try object(state.appendingPathComponent("delivery.json"))["at"] as? String)
        XCTAssertFalse(at.hasSuffix("Z"), at)
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxxxx"
        let moment = try XCTUnwrap(reader.date(from: at), "\(at) is RFC 3339 with an offset")
        let offset = TimeZone.current.secondsFromGMT(for: moment)
        let sign = offset < 0 ? "-" : "+"
        XCTAssertEqual(String(at.suffix(6)), String(format: "%@%02d:%02d", sign, abs(offset) / 3600, abs(offset) % 3600 / 60), "\(at) is in this host's offset")
    }
}

final class ReachedDeliveryTests: TelemetryCase {
    /// The app the collector's MOBILE_ANALYTICS_APPS_JSON declares for these cases.
    private func declaredApp() throws -> String {
        try required("WISENT_TELEMETRY_TEST_APP_ID", "an app the collector's MOBILE_ANALYTICS_APPS_JSON declares")
    }

    func test_an_event_reaches_the_collector() throws {
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", try collector(), 1)
        let telemetry = telemetry(app: try declaredApp())
        try telemetry.setLevel(.errors)
        // The failure starts the send itself; settled is once it ended.
        settle(telemetry, try sampleFailure(), causeID: "pairs-unreadable")
        let kept = try object(state.appendingPathComponent("delivery.json"))
        XCTAssertEqual(kept["sent"] as? Int, 1)
        XCTAssertEqual(kept["remaining"] as? Int, 0)
        XCTAssertTrue(kept["stopped"] is NSNull, "\(kept)")
        XCTAssertEqual(try queuedOnDisk(), [], "the accepted event left the queue")
        XCTAssertEqual(telemetry.status()["queued"] as? Int, 0)
    }

    func test_an_app_the_collector_does_not_declare_stays_queued_with_its_refusal() async throws {
        let address = try collector()
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", address, 1)
        let telemetry = telemetry(app: "wisent-errors-test-undeclared")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        let event = try onlyEvent(telemetry)
        let delivered = await telemetry.flush()
        // The collector's own answer to the same event: HTTP 403
        // (https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.4) with its declared cause.
        let answer = try await ask(address, posting: event.body)
        XCTAssertEqual(answer.status, 403, answer.body)
        let said = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(answer.body.utf8)) as? [String: Any], answer.body)
        XCTAssertEqual(said["cause"] as? String, "app-undeclared", answer.body)
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.remaining, 1)
        let refusal = "sending event \(event.id) to \(address): the collector refused HTTP \(answer.status): \(answer.body)\(oneWaits); fix: the answer names what the collector refuses and how to fix it; when its cause is app-undeclared, declare app wisent-errors-test-undeclared in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON with its collector URL and an analytics backend; the events are sent again on the next flush"
        XCTAssertEqual(delivered.stopped, refusal)
        let kept = try object(state.appendingPathComponent("delivery.json"))
        XCTAssertEqual((kept["stopped"] as? [String: Any])?["detail"] as? String, refusal)
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the refused event still waits")
    }

    func test_a_collector_failing_on_its_side_keeps_the_events_with_its_own_failure() async throws {
        let failing = try required(
            "WISENT_TELEMETRY_TEST_FAILING_COLLECTOR",
            "a collector deployment that answers with a server error, such as an Echo that cannot reach its database")
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", failing, 1)
        // The collector checks the app before it writes: only an app it
        // declares reaches the store that fails.
        let telemetry = telemetry(app: try declaredApp())
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        let event = try onlyEvent(telemetry)
        let delivered = await telemetry.flush()
        // The 5xx server error class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6
        let answer = try await ask(failing, posting: event.body)
        XCTAssertTrue((500..<600).contains(answer.status), "\(answer.status) \(answer.body)")
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.remaining, 1)
        XCTAssertEqual(
            delivered.stopped,
            "sending event \(event.id) to \(failing): the collector failed on its own side, HTTP \(answer.status): \(answer.body)\(oneWaits); fix: nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported with `wisent-errors-test support report`, or from an app's Help → Report a Problem")
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the event still waits")
    }

    func test_an_address_that_is_not_a_collector_is_named() async throws {
        let elsewhere = try origin(try collector(), before: "/api/") + "/robots.txt"
        setenv("WISENT_TELEMETRY_COLLECTOR_URL", elsewhere, 1)
        let telemetry = telemetry(app: "wisent-errors-test-desktop")
        try telemetry.setLevel(.errors)
        settle(telemetry, try sampleFailure())
        let event = try onlyEvent(telemetry)
        let delivered = await telemetry.flush()
        let answer = try await ask(elsewhere, posting: event.body)
        XCTAssertEqual(delivered.sent, 0)
        XCTAssertEqual(delivered.remaining, 1)
        XCTAssertEqual(
            delivered.stopped,
            "reading the collector's answer to event \(event.id): the answer is not the collector's {\"ok\": true}: \(answer.body); observed: HTTP \(answer.status) from \(elsewhere); fix: check that \(elsewhere) is the Echo app collector, /api/analytics/mobile/collect")
        XCTAssertEqual(try queuedOnDisk(), [event.id], "the event still waits")
    }
}
