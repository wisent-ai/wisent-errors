// Delivering what telemetry queued: the queue sent to the collector oldest
// first, each event dropped once the collector accepts it, and the outcome
// kept in `delivery.json` (docs/telemetry.md).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension WisentTelemetry {
    /// Send the queue on a detached task; `settled` runs when the attempt ends.
    public func flushInBackground(settled: @escaping @Sendable () -> Void = {}) {
        Task.detached(priority: .utility) { [self] in
            if let stopped = await self.flush().stopped { Self.say(stopped) }
            settled()
        }
    }

    /// What one flush did: how many went, how many wait, and why it stopped.
    public struct Delivered: Sendable {
        public let sent: Int
        public let remaining: Int
        public let stopped: String?
        public let skipped: String?
    }

    /// Send every queued event oldest first, dropping each the collector
    /// accepted; the first refusal or transport error stops it, and the
    /// outcome is kept in `delivery.json`.
    public func flush() async -> Delivered {
        let events: [[String: Any]]
        do { events = try queued() } catch { return Delivered(sent: 0, remaining: 0, stopped: "\(error)", skipped: nil) }
        if Self.doNotTrack { return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "DO_NOT_TRACK") }
        switch (try? level()) ?? nil {
        case nil: return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "unanswered")
        case .off?: return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "off")
        default: break
        }
        let target: URL
        do {
            target = try collector().url
        } catch {
            let delivered = Delivered(sent: 0, remaining: events.count, stopped: "\(error)", skipped: nil)
            keep(delivered)
            return delivered
        }
        var sent = 0
        var stopped: String?
        for (index, event) in events.enumerated() {
            let eventID = event["eventId"] as? String ?? ""
            let waiting = events.count - index
            switch await post(event, to: target) {
            case .accepted:
                if let path = file("queue")?.appendingPathComponent("\(eventID).json") {
                    try? FileManager.default.removeItem(at: path)
                }
                sent += 1
                continue
            case .refused(let status, let answer):
                stopped = "sending event \(eventID) to \(target.absoluteString): the collector refused HTTP \(status): \(answer); observed: \(waiting) event(s) stay queued; fix: the answer names what the collector refuses; when it is Unknown mobile analytics app, declare app \(product.appID) in the Echo deployment's MOBILE_ANALYTICS_APPS_JSON; the events are sent again on the next flush"
            case .failed(let status, let answer):
                stopped = "sending event \(eventID) to \(target.absoluteString): the collector failed on its own side, HTTP \(status): \(answer); observed: \(waiting) event(s) stay queued; fix: nothing on this machine is to fix: the events are sent again on the next flush; a collector that keeps failing is reported from Help → Report a Problem"
            case .notCollector(let status, let answer):
                stopped = "reading the collector's answer to event \(eventID): the answer is not the collector's {\"ok\": true}: \(answer); observed: HTTP \(status) from \(target.absoluteString); fix: check that \(target.absoluteString) is the Echo app collector, /api/analytics/mobile/collect"
            case .unreachable(let cause):
                stopped = "sending event \(eventID) to \(target.absoluteString): the collector could not be reached: \(cause); observed: \(waiting) event(s) stay queued; fix: nothing to do: the events are sent on the next flush once the network or the collector is back"
            }
            break
        }
        let delivered = Delivered(sent: sent, remaining: events.count - sent, stopped: stopped, skipped: nil)
        keep(delivered)
        return delivered
    }

    private enum Answer {
        case accepted
        case refused(Int, String)
        case failed(Int, String)
        case notCollector(Int, String)
        case unreachable(String)
    }

    private func post(_ event: [String: Any], to url: URL) async -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: event)
        let session = self.session
        return await withCheckedContinuation { (answered: CheckedContinuation<Answer, Never>) in
            session.dataTask(with: request) { data, response, error in
                if let error { return answered.resume(returning: .unreachable(error.localizedDescription)) }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                if (200..<300).contains(status), object?["ok"] as? Bool == true {
                    return answered.resume(returning: .accepted)
                }
                // A server error is the collector's own failure, whatever its
                // body; below that, the collector refuses with a JSON object.
                if status >= 500 {
                    return answered.resume(returning: .failed(status, body))
                }
                if !(200..<300).contains(status), object != nil {
                    return answered.resume(returning: .refused(status, body))
                }
                answered.resume(returning: .notCollector(status, body))
            }.resume()
        }
    }

    private func keep(_ delivered: Delivered) {
        guard let path = file("delivery.json") else { return }
        let record: [String: Any] = [
            "at": Self.now(),
            "sent": delivered.sent,
            "remaining": delivered.remaining,
            "stopped": delivered.stopped.map { ["detail": $0] } as Any? ?? NSNull(),
            "skipped": delivered.skipped as Any? ?? NSNull(),
        ]
        do { try writeObject(record, to: path, what: "the last delivery") } catch { Self.say(error) }
    }
}
